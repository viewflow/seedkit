#!/usr/bin/env bash
#
# Loop over seedkit-examples/logs/*.log, ask a fresh claude -p to review
# each one against the skill, apply short fixes where a real defect is
# present, commit + push the submodule + parent pointer, then delete the
# log. One log at a time, sequential.
#
# Same session + watchdog + pgrp sweep mechanics as run-tests.sh so a
# stuck sub-claude can't livelock the loop.
#
# Usage:
#   ./review-logs.sh                    # review every *.log in the logs dir
#   ./review-logs.sh 02-shop-20260510-173829.log    # single file (basename)
#   MODEL=claude-sonnet-4-6 ./review-logs.sh
#   TIMEOUT_PER_LOG=1800 ./review-logs.sh
#
# Requires: claude CLI, python3, git.

set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
PARENT="$(cd "$REPO/.." && pwd)"
LOGS_DIR="${LOGS_DIR:-$PARENT/seedkit-examples/logs}"
MODEL="${MODEL:-claude-opus-4-7}"
TIMEOUT_PER_LOG="${TIMEOUT_PER_LOG:-3600}"

command -v claude  >/dev/null || { echo "claude CLI not found in PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found in PATH"; exit 1; }
command -v git     >/dev/null || { echo "git not found in PATH"; exit 1; }

setsid_exec() {
    exec python3 -c '
import os, sys
os.setsid()
os.execvp(sys.argv[1], sys.argv[1:])
' "$@"
}

# Resolve targets: explicit basenames as args, or all *.log files.
shopt -s nullglob
declare -a LOGS=()
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        if [[ -f "$arg" ]]; then
            LOGS+=("$arg")
        elif [[ -f "$LOGS_DIR/$arg" ]]; then
            LOGS+=("$LOGS_DIR/$arg")
        else
            echo "skip: '$arg' not found" >&2
        fi
    done
else
    LOGS=("$LOGS_DIR"/*.log)
fi

if [[ ${#LOGS[@]} -eq 0 ]]; then
    echo "no logs to review under $LOGS_DIR"
    exit 0
fi

# Refuse to start if the submodule or parent has unrelated pending work
# — we'd attribute it to the wrong log otherwise.
if ! git -C "$REPO" diff-index --quiet HEAD --; then
    echo "seedkit submodule has uncommitted changes — commit or stash first" >&2
    exit 1
fi
if ! git -C "$PARENT" diff-index --quiet HEAD -- seedkit; then
    echo "parent repo has uncommitted seedkit pointer drift — bump or stash first" >&2
    exit 1
fi

# The agent receives this as a single prompt. LOGPATH is substituted per
# iteration. The agent has full tool access via --dangerously-skip-permissions.
read -r -d '' PROMPT_TEMPLATE <<'EOF' || true
Review the seedkit testcase log at:

    LOGPATH

The log has two phases — `════════ BUILD ════════` (agent scaffolding a Django project from the seedkit skill) and `════════ REVIEW ════════` (a fresh claude -p auditing the result). Both end at `════════ DONE ════════`.

Workflow:

1. Read the log. Identify items that point at a real **skill defect** — a reference snippet that was wrong, missing, or led the agent into a footgun. Skip:
   - Agent improvisations against strict testcase assertions (e.g. agent put healthchecks in `api/views.py` when the skill allows any registered app).
   - Findings already covered by an existing reference or `SKILL.md` pitfall — grep before editing.
   - Cosmetic preferences and "consider adding X" nudges.
2. For each real defect, make the smallest edit to the matching `skills/seedkit/SKILL.md`, `skills/seedkit/references/*.md`, or `testcases/*.md`. Follow `seedkit/CLAUDE.md`:
   - Show the correct sample. Drop redundant "don't" prose if the positive sample covers it.
   - No significance inflation, no fake -ing analysis, no podium voice.
   - Cross-reference, don't duplicate.
3. If nothing real surfaces, that's a valid outcome — say "no skill change" and move to step 4.
4. Inside `/Users/kmmbvnr/Workspace/Robusta/seedkit/`: `git add -A`, then if anything changed commit and `git push origin main`. Use the host gitconfig — never pass `--author` or `-c user.email`.
5. Inside `/Users/kmmbvnr/Workspace/Robusta/`: `git add seedkit`, commit `chore: bump seedkit/ — <one-line reason>`, push.
6. `rm` the log file at LOGPATH (it's gitignored — plain `rm`, not `git rm`).
7. Final line: `[<log basename>] <one sentence outcome>`.

Hard constraints:
- Don't run `./run-tests.sh` or otherwise spawn a build.
- Don't invoke any skill.
- Don't commit unrelated files. If `git status` shows drift you didn't introduce, stop and report.
- Keep every edit short.
EOF

for log in "${LOGS[@]}"; do
    name=$(basename "$log")
    echo
    echo "==> $name"

    if [[ ! -f "$log" ]]; then
        echo "    skip: file vanished"
        continue
    fi

    prompt="${PROMPT_TEMPLATE//LOGPATH/$log}"
    start=$(date +%s)

    setsid_exec claude -p "$prompt" \
        --dangerously-skip-permissions \
        --model="$MODEL" \
        --output-format text \
        --print &
    pid=$!
    pgid=$pid

    (
        sleep "$TIMEOUT_PER_LOG"
        if kill -0 "$pid" 2>/dev/null; then
            echo >&2
            echo "[review-logs] $name exceeded ${TIMEOUT_PER_LOG}s — killing pgrp $pgid" >&2
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

    # Sweep stragglers — git push / claude spawn things.
    kill -TERM -- -"$pgid" 2>/dev/null || true
    sleep 1
    kill -KILL -- -"$pgid" 2>/dev/null || true

    duration=$(( $(date +%s) - start ))
    echo "    exit: $rc  duration: ${duration}s"
done

echo
echo "done."
