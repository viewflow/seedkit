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
command -v jq      >/dev/null || { echo "jq not found in PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found in PATH"; exit 1; }
command -v git     >/dev/null || { echo "git not found in PATH"; exit 1; }

# Keep the Mac awake while we run (macOS only; no-op elsewhere). The
# `-w $$` ties caffeinate to this shell, so it exits with the script.
if command -v caffeinate >/dev/null; then
    caffeinate -i -w $$ &
fi

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
7. Don't touch CHANGELOG.md or SKILL.md `version:` — the final pass after the loop consolidates them in one shot.
8. Final line: `[<log basename>] <one sentence outcome>`.

Hard constraints:
- Don't run `./run-tests.sh` or otherwise spawn a build.
- Don't invoke any skill.
- Don't commit unrelated files. If `git status` shows drift you didn't introduce, stop and report.
- Keep every edit short.
EOF

total=${#LOGS[@]}
idx=0
declare -a RESULTS=()

for log in "${LOGS[@]}"; do
    idx=$((idx + 1))
    name=$(basename "$log")
    echo
    echo "==> ($idx/$total) $name"
    echo "    log:   $log"
    echo "    model: $MODEL"

    if [[ ! -f "$log" ]]; then
        echo "    skip: file vanished"
        RESULTS+=("skip   $name")
        continue
    fi

    prompt="${PROMPT_TEMPLATE//LOGPATH/$log}"
    start=$(date +%s)

    # stream-json + jq pulls text_delta events out token-by-token so the
    # sub-claude's progress shows live; --output-format text would buffer
    # until the run finishes.
    PROMPT="$prompt" CASE_MODEL="$MODEL" \
    setsid_exec bash -c '
        claude -p "$PROMPT" \
            --dangerously-skip-permissions \
            --model="$CASE_MODEL" \
            --output-format stream-json \
            --include-partial-messages \
            --print \
            --verbose \
        | jq --unbuffered -j -r '\''select(.event.delta.type? == "text_delta") | .event.delta.text'\''
        exit "${PIPESTATUS[0]}"
    ' &
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
    printf '    done: exit=%s duration=%ss [%d/%d]\n' "$rc" "$duration" "$idx" "$total"
    RESULTS+=("$(printf 'exit=%-3s %5ss  %s' "$rc" "$duration" "$name")")
done

echo
echo "════════ summary ════════"
for line in "${RESULTS[@]}"; do
    echo "    $line"
done

# Final pass: roll the per-log commits into one high-level CHANGELOG bullet.
echo
echo "════════ changelog ════════"

TODAY_VER=$(date +%y.%V.%u)
read -r -d '' CHANGELOG_TEMPLATE <<'EOF' || true
Consolidate today's skill changes into the changelog.

Today's version (year/ISO-week/ISO-weekday): **__TODAY__**

1. Bump the version to **__TODAY__** in both files:
   - `/Users/kmmbvnr/Workspace/Robusta/seedkit/.claude-plugin/plugin.json` → set `"version": "__TODAY__"`.
   - `/Users/kmmbvnr/Workspace/Robusta/seedkit/skills/seedkit/SKILL.md` frontmatter → set `version: __TODAY__`.
   The date drives the version — bumping on a fresh day; staying the same within a day.
2. Read `/Users/kmmbvnr/Workspace/Robusta/seedkit/CHANGELOG.md`. If a `## __TODAY__ — ` section already exists, edit it in place; otherwise insert a new section at the top under the `# Changelog` heading.
3. Run `git -C /Users/kmmbvnr/Workspace/Robusta/seedkit log --pretty=format:'%h %s' --since='24 hours ago'` to find commits worth recording. Batch related commits into ONE short bullet per theme — never one bullet per commit. Use Keep-a-Changelog headings (`### Added` / `### Changed` / `### Fixed` / `### Removed`), one-line bullets, high-level, user-facing.
4. If an existing bullet in today's section covers a new commit, extend it instead of adding a duplicate.
5. If CHANGELOG.md is longer than 200 lines after the edit, trim the **oldest** sections at the bottom to bring it back near 150 lines. Git keeps the dropped history.
6. Commit the three files (plugin.json + SKILL.md + CHANGELOG.md) inside seedkit with message `docs: __TODAY__ changelog`. Push. Then in the parent repo `git add seedkit`, commit `chore: bump seedkit/ — __TODAY__ changelog`, push.
7. Final line: `[changelog] <one sentence>`.

Hard constraints:
- Don't touch any other file.
- Don't invoke any skill.
- Use the host gitconfig — no `--author` overrides.
- One bullet per theme. If nothing in the past 24h is meaningful, say "no changelog update" and skip the commit.
EOF
CHANGELOG_PROMPT="${CHANGELOG_TEMPLATE//__TODAY__/$TODAY_VER}"

PROMPT="$CHANGELOG_PROMPT" CASE_MODEL="$REVIEW_MODEL" \
setsid_exec bash -c '
    claude -p "$PROMPT" \
        --dangerously-skip-permissions \
        --model="$CASE_MODEL" \
        --output-format stream-json \
        --include-partial-messages \
        --print \
        --verbose \
    | jq --unbuffered -j -r '\''select(.event.delta.type? == "text_delta") | .event.delta.text'\''
    exit "${PIPESTATUS[0]}"
' &
cpid=$!
cpgid=$cpid

( sleep 600
  if kill -0 "$cpid" 2>/dev/null; then
      echo "[review-logs] changelog step exceeded 600s — killing pgrp $cpgid" >&2
      kill -TERM -- -"$cpgid" 2>/dev/null || true
      sleep 5
      kill -KILL -- -"$cpgid" 2>/dev/null || true
  fi
) &
cwatch=$!
wait "$cpid"; crc=$?
kill "$cwatch" 2>/dev/null || true; wait "$cwatch" 2>/dev/null || true
kill -TERM -- -"$cpgid" 2>/dev/null || true; sleep 1; kill -KILL -- -"$cpgid" 2>/dev/null || true

echo
echo "done."
