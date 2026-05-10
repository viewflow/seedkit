#!/usr/bin/env bash
#
# Run seedkit testcases through `claude -p` one at a time.
#
# Each case runs in seedkit/workspace/ (gitignored). Workspace is wiped
# before every case so projects don't bleed into each other. Per-case stream
# logs and a Markdown summary land in workspace/logs/.
#
# Usage:
#   ./run-tests.sh                          # run all testcases
#   ./run-tests.sh 02 07                    # run specific ones (number prefix is enough)
#   MODEL=claude-opus-4-7 ./run-tests.sh    # override model
#
# Requires: claude CLI, jq.

set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TESTCASES="$REPO/testcases"
WORKSPACE="$REPO/workspace"
LOGS="$WORKSPACE/logs"
MODEL="${MODEL:-claude-sonnet-4-6}"
# Hard ceiling per case. The seedkit agent occasionally improvises a bash
# command (e.g. `uv run celery worker` followed by `kill %1`) that orphans a
# forking child tree under PID 1; bash's `wait` then blocks forever and the
# claude turn never advances. The watchdog below puts each case in its own
# session and kills the whole process group when this elapses or when the
# claude pipeline exits.
TIMEOUT_PER_CASE="${TIMEOUT_PER_CASE:-7200}"
STAMP="$(date +%Y%m%d-%H%M%S)"
SUMMARY="$LOGS/summary-$STAMP.md"

command -v claude  >/dev/null || { echo "claude CLI not found in PATH"; exit 1; }
command -v jq      >/dev/null || { echo "jq not found in PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found in PATH"; exit 1; }

mkdir -p "$LOGS"

# Resolve the testcase files to run.
shopt -s nullglob
declare -a FILES=()
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        # Accept full path, basename, or just the leading number.
        if [[ -f "$arg" ]]; then
            FILES+=("$arg")
        elif [[ -f "$TESTCASES/$arg" ]]; then
            FILES+=("$TESTCASES/$arg")
        elif [[ -f "$TESTCASES/$arg.md" ]]; then
            FILES+=("$TESTCASES/$arg.md")
        else
            matches=("$TESTCASES/$arg"-*.md)
            if [[ ${#matches[@]} -eq 1 ]]; then
                FILES+=("${matches[0]}")
            else
                echo "skip: '$arg' did not match a single testcase" >&2
            fi
        fi
    done
else
    FILES=("$TESTCASES"/[0-9][0-9]-*.md)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "no testcases to run" >&2
    exit 1
fi

{
    echo "# Cookiecutter test run — $STAMP"
    echo
    echo "- model: \`$MODEL\`"
    echo "- workspace: \`$WORKSPACE\`"
    echo "- cases: ${#FILES[@]}"
    echo
} > "$SUMMARY"

cleanup_workspace() {
    # Remove everything in workspace EXCEPT the logs directory.
    find "$WORKSPACE" -mindepth 1 -maxdepth 1 ! -name 'logs' -exec rm -rf {} +
}

# Portable setsid: macOS has no setsid by default. Python's os.setsid + execvp
# does the same thing — make the launched process a session leader so its PGID
# equals its PID, and every descendant (orphaned celery / gunicorn / manage.py)
# stays in that group. After the case finishes we `kill -- -<pgid>` to sweep
# anything that outlived the claude turn.
setsid_exec() {
    exec python3 -c '
import os, sys
os.setsid()
os.execvp(sys.argv[1], sys.argv[1:])
' "$@"
}

link_skill() {
    # Expose the seedkit skill to claude -p as a project-scoped skill.
    # Without this the sub-claude can't find it and falls back to ad-hoc behavior.
    mkdir -p "$WORKSPACE/.claude/skills"
    ln -snf "$REPO/skills/seedkit" "$WORKSPACE/.claude/skills/seedkit"
}

cleanup_workspace
link_skill

for tc in "${FILES[@]}"; do
    name=$(basename "$tc" .md)
    log="$LOGS/$name-$STAMP.log"
    echo
    echo "==> $name"
    echo "    log:    $log"
    echo "    prompt: $tc"

    cd "$WORKSPACE"

    # Marker so we can identify REVIEW.md files written *during* this case.
    # Without it, prior cases' REVIEW.md leak into later cases' summary rows
    # (workspace is wiped only at the start of the run, not between cases).
    marker="$LOGS/.start-$name-$STAMP"
    touch "$marker"

    start=$(date +%s)

    # Run the claude pipeline in its own session so we can clean up the
    # entire process tree afterwards (including orphans whose parent died).
    PROMPT="$(cat "$tc")" CASE_LOG="$log" CASE_MODEL="$MODEL" \
    setsid_exec bash -c '
        claude -p "$PROMPT" \
            --dangerously-skip-permissions \
            --model="$CASE_MODEL" \
            --output-format stream-json \
            --include-partial-messages \
            --print \
            --verbose \
        | jq --unbuffered -j -r '\''select(.event.delta.type? == "text_delta") | .event.delta.text'\'' \
        | tee "$CASE_LOG"
        exit "${PIPESTATUS[0]}"
    ' &
    case_pid=$!
    case_pgid=$case_pid    # session leader's PID == its PGID

    # Watchdog: terminate the whole group if the case overruns.
    (
        sleep "$TIMEOUT_PER_CASE"
        if kill -0 "$case_pid" 2>/dev/null; then
            echo >&2
            echo "[run-tests] $name exceeded ${TIMEOUT_PER_CASE}s — killing pgrp $case_pgid" >&2
            kill -TERM -- -"$case_pgid" 2>/dev/null || true
            sleep 5
            kill -KILL -- -"$case_pgid" 2>/dev/null || true
        fi
    ) &
    watchdog=$!

    wait "$case_pid"
    rc=$?

    # Stand the watchdog down if the case finished on its own.
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true

    # Sweep orphans that outlived the claude turn (celery worker pools,
    # rqworker, gunicorn, runserver autoreloader). They share our PGID
    # because setsid put the whole subtree there.
    kill -TERM -- -"$case_pgid" 2>/dev/null || true
    sleep 1
    kill -KILL -- -"$case_pgid" 2>/dev/null || true

    end=$(date +%s)
    duration=$((end - start))

    {
        printf '\n[exit: %s, duration: %ss]\n' "$rc" "$duration"
    } >> "$log"

    # Only REVIEW.md files newer than the marker belong to this case.
    review=$(find "$WORKSPACE" -mindepth 2 -name 'REVIEW.md' -not -path "*/logs/*" -newer "$marker" 2>/dev/null | head -1)
    rm -f "$marker"

    {
        echo "## $name"
        echo
        echo "- exit: \`$rc\`"
        echo "- duration: ${duration}s"
        echo "- log: \`logs/$(basename "$log")\`"
        if [[ -n "$review" && -s "$review" ]]; then
            echo "- REVIEW.md (\`$(realpath --relative-to="$WORKSPACE" "$review" 2>/dev/null || echo "$review")\`):"
            echo
            echo '<details><summary>show</summary>'
            echo
            cat "$review"
            echo
            echo '</details>'
        else
            echo "- REVIEW.md: (not produced)"
        fi
        echo
    } >> "$SUMMARY"
done

echo
echo "Summary: $SUMMARY"
