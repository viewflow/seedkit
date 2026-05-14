#!/usr/bin/env bash
#
# Generate the "no-skill" baseline for each testcase: a fresh claude -p
# with no /seedkit skill loaded, given just the ## Prompt section, into
# seedkit-examples/baselines/<case>/. No boot smoke, no deploy smoke,
# no review — just the raw output of an unaided AI.
#
# The baselines are the control group: comparing them against the
# skill-generated projects under seedkit-examples/NN-*/ shows what the
# skill adds.
#
# Manual invocation — run once, refresh by hand when the testcases
# change or the model changes.
#
#   ./run-baseline.sh                       # all testcases
#   ./run-baseline.sh 02 07                 # specific ones (matched by NN prefix)
#   MODEL=claude-opus-4-7 ./run-baseline.sh
#
# Requires: claude CLI, jq, python3.

set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TESTCASES="$REPO/testcases"
WORKSPACE="${WORKSPACE:-$REPO/../seedkit-examples}"
WORKSPACE="$(cd "$WORKSPACE" && pwd)"
BASELINE_ROOT="$WORKSPACE/baselines"
LOGS="$WORKSPACE/logs"
MODEL="${MODEL:-claude-sonnet-4-6}"
TIMEOUT_PER_CASE="${TIMEOUT_PER_CASE:-3600}"
STAMP="$(date +%Y%m%d-%H%M%S)"

command -v claude  >/dev/null || { echo "claude CLI not found in PATH"; exit 1; }
command -v jq      >/dev/null || { echo "jq not found in PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found in PATH"; exit 1; }

if command -v caffeinate >/dev/null; then
    caffeinate -i -w $$ &
fi

mkdir -p "$LOGS" "$BASELINE_ROOT"

# Resolve the testcase files to run.
shopt -s nullglob
declare -a FILES=()
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
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

extract_section() {
    local file=$1 section=$2
    awk -v want="$section" '
        /^## / { capture = ($0 == "## " want); next }
        capture { print }
    ' "$file"
}

setsid_exec() {
    exec python3 -c '
import os, sys
os.setsid()
os.execvp(sys.argv[1], sys.argv[1:])
' "$@"
}

declare -a RESULTS=()

for tc in "${FILES[@]}"; do
    name=$(basename "$tc" .md)
    prefix="${name%%-*}-"   # `02-shop` → `02-`

    # Pick the case dir name from the matching skill output if it
    # exists, so baseline and skill outputs share folder names. Falls
    # back to the testcase basename otherwise.
    case_dir_name="$name"
    for match in "$WORKSPACE/$prefix"*/; do
        [[ -d "$match" ]] || continue
        match_name="$(basename "$match")"
        [[ "$match_name" == "baselines" ]] && continue
        case_dir_name="$match_name"
        break
    done

    case_dir="$BASELINE_ROOT/$case_dir_name"
    log="$LOGS/baseline-$name-$STAMP.log"

    echo
    echo "==> $name"
    echo "    out:   $case_dir"
    echo "    log:   $log"

    rm -rf "$case_dir"
    mkdir -p "$case_dir"
    : > "$log"

    prompt_section=$(extract_section "$tc" "Prompt")

    # Strip the leading `/seedkit` / `/seedkit-slim` invocation — with
    # no skill loaded, that line is dead text and biases the agent.
    prompt_body=$(printf '%s\n' "$prompt_section" \
        | sed -E '/^\/seedkit(-slim)?$/d')

    prompt="Bootstrap a Django project per the answers below. Use whatever conventions you think are best — there is no skill loaded.

Work strictly inside the current working directory. Do not read, list, or reference any path outside it (no \`ls ..\`, no \`Read ../...\`, no \`Glob ../**\`). This is a fresh control-group run — sibling directories may contain unrelated projects and looking at them would bias the output.

$prompt_body"

    {
        echo "════════ BASELINE ($MODEL) ════════"
        echo "testcase: $tc"
        echo "out:      $case_dir"
        echo
    } >> "$log"

    start=$(date +%s)

    pushd "$case_dir" >/dev/null

    PROMPT="$prompt" CASE_LOG="$log" CASE_MODEL="$MODEL" \
    setsid_exec bash -c '
        claude -p "$PROMPT" \
            --dangerously-skip-permissions \
            --model="$CASE_MODEL" \
            --output-format stream-json \
            --include-partial-messages \
            --print \
            --verbose \
        | jq --unbuffered -j -r '\''select(.event.delta.type? == "text_delta") | .event.delta.text'\'' \
        | tee -a "$CASE_LOG"
        exit "${PIPESTATUS[0]}"
    ' &
    pid=$!
    pgid=$pid

    (
        sleep "$TIMEOUT_PER_CASE"
        if kill -0 "$pid" 2>/dev/null; then
            echo >&2
            echo "[run-baseline] $name exceeded ${TIMEOUT_PER_CASE}s — killing pgrp $pgid" >&2
            kill -TERM -- -"$pgid" 2>/dev/null || true
            sleep 5
            kill -KILL -- -"$pgid" 2>/dev/null || true
        fi
    ) &
    watchdog=$!

    wait "$pid"
    rc=$?

    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true

    kill -TERM -- -"$pgid" 2>/dev/null || true
    sleep 1
    kill -KILL -- -"$pgid" 2>/dev/null || true

    popd >/dev/null

    duration=$(( $(date +%s) - start ))
    {
        echo
        echo "════════ DONE ════════"
        printf '[exit: %s, duration: %ss]\n' "$rc" "$duration"
    } >> "$log"

    printf '    done: exit=%s duration=%ss\n' "$rc" "$duration"
    RESULTS+=("$(printf 'exit=%-3s %5ss  %s' "$rc" "$duration" "$name")")
done

echo
echo "════════ summary ════════"
for line in "${RESULTS[@]}"; do
    echo "    $line"
done
echo
echo "baselines under: $BASELINE_ROOT"
