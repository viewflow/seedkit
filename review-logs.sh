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
CURRENT_BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [[ "$CURRENT_BRANCH" == "main" ]] && git -C "$PARENT" rev-parse --git-dir >/dev/null 2>&1; then
    if ! git -C "$PARENT" diff-index --quiet HEAD -- seedkit; then
        echo "parent repo has uncommitted seedkit pointer drift — bump or stash first" >&2
        exit 1
    fi
fi

# The agent receives this as a single prompt. LOGPATH and TODAY are
# substituted per iteration. The agent has full tool access via
# --dangerously-skip-permissions.
read -r -d '' PROMPT_TEMPLATE <<'EOF' || true
Review the seedkit-slim testcase log at:

    LOGPATH

Today's version (year/ISO-week/ISO-weekday): **__TODAY__**

The log has two phases — `════════ BUILD ════════` (agent scaffolding a Django project from the seedkit-slim skill) and `════════ REVIEW ════════` (a fresh claude -p auditing the result). Both end at `════════ DONE ════════`.

Workflow:

1. Read the log. Identify three categories of real **skill defects**:

   a. **Error loops** — sequences where the agent generated code, hit an error (ImportError, ImproperlyConfigured, migration failure, server crash, curl returning non-200, etc.), then had to patch it. Each loop is a missing or wrong snippet in the skill. Extract the working fix.

   b. **Wrong/missing snippets** — a reference snippet that was incorrect, incomplete, or absent, causing the agent to improvise or skip a required step.

   c. **Silent omissions in the generated artefact.** Slim deliberately drops workflow guidance from `SKILL.md`. The boot smoke may pass while the project still ships a known footgun (breaks in prod, breaks on next deploy, breaks on next contributor's clone). Derive the case prefix `NN` from the log basename (e.g. `02-shop-20260510-173829.log` → `02`) and locate the project dir at `__WORKSPACE__/NN-*/`. From that dir, run the checklist below — each non-empty hit (or `MISSING:` line) is a defect to treat like (b):

      ```sh
      # uv inside Docker/compose/fly — must be `python manage.py`, not `uv run`
      grep -nH 'uv run' Dockerfile docker-compose.yml docker-compose.prod.yml fly.toml 2>/dev/null

      # Python version pin
      grep -H '^requires-python' pyproject.toml || echo "MISSING: requires-python in pyproject.toml"

      # Duplicate DATABASES block left behind by startproject
      grep -rn '^DATABASES = {' . --include='*.py' 2>/dev/null | awk -F: '{print $1}' | sort | uniq -c | awk '$1>1'

      # tasks.py at project root or under config/ — must live inside a registered app
      find . -maxdepth 3 -name tasks.py -not -path './.venv/*' -not -path './.git/*' \
        | grep -E '^\./tasks\.py$|/config/tasks\.py$' || true

      # .env.example trailing comments after values (django-environ reads the comment as part of the URL)
      grep -nE '^[A-Z_]+=[^#]*[[:space:]]+#' .env.example 2>/dev/null

      # Canonical DJANGO_* env vars
      for v in DJANGO_DEBUG DJANGO_SECRET_KEY DJANGO_ALLOWED_HOSTS; do
        grep -q "^$v=" .env.example 2>/dev/null || echo "MISSING: $v in .env.example"
      done

      # Fail-fast idiom for prod secrets (settings should reference env.NOTSET when DEBUG=False)
      grep -rn 'env.NOTSET\|NOTSET' --include='*.py' . 2>/dev/null | head -3 \
        || echo "MISSING: env.NOTSET fail-fast in settings"

      # If deploy=vps or github-ssh, README's ## Deploy block must run migrate before `compose up -d`
      grep -A20 '^## Deploy' README.md 2>/dev/null | grep -qE 'migrate.*\n.*compose up' \
        || grep -B2 'compose up -d' README.md | grep -q migrate \
        || echo "CHECK: README ## Deploy may be missing pre-up migrate step (skip if deploy=none/managed)"
      ```

   Skip:
   - Agent improvisations against strict testcase assertions (e.g. agent put healthchecks in `api/views.py` when the skill allows any registered app).
   - Findings already covered by an existing reference or `SKILL.md` pitfall — grep before editing.
   - Cosmetic preferences and "consider adding X" nudges.
   - Checklist items that aren't applicable to this case's configuration (no Docker artefact when deploy=none; no `## Deploy` block when deploy=none/managed).

2. For each real defect, make the smallest edit to the matching `skills/seedkit-slim/SKILL.md` or `skills/seedkit-slim/references/*.md`. **Create `skills/seedkit-slim/references/<tool>.md` if no file exists yet for the relevant package.** Follow `seedkit/CLAUDE.md` and these rules:
   - **Tool-specific guidance belongs in a reference file.** If an implementation detail is specific to a single package or tool (e.g. Celery broker config, WhiteNoise middleware order, allauth URL wiring), put it in `skills/seedkit-slim/references/<tool>.md` and cross-reference from `SKILL.md` — do not inline it in `SKILL.md`.
   - **Error-loop fixes go into snippets, not prose.** When an error loop reveals the correct wiring, add the working code as a paste-ready snippet in the reference file. One short rationale comment inside the snippet if the reason isn't obvious; no surrounding explanation paragraph.
   - **No negative samples when a positive one exists.** If the correct approach is shown with a code sample, do not add a "Don't do X" / "Never use Y" counterexample alongside it. Add negative guidance only when there is no positive sample that already covers the behavior (e.g. a standalone rule with no code equivalent).
   - Show the correct sample. No significance inflation, no fake -ing analysis, no podium voice.
   - Cross-reference, don't duplicate.
3. If nothing real surfaces, that's a valid outcome — say "no skill change", skip to step 7.
4. Bump the version to **__TODAY__** in both files (only if you made an edit in step 2):
   - `__REPO__/.claude-plugin/plugin.json` → set `"version": "__TODAY__"`.
   - `__REPO__/skills/seedkit-slim/SKILL.md` frontmatter → set `version: __TODAY__`.
5. Update `__REPO__/CHANGELOG.md`: if a `## __TODAY__ — ` section already exists, extend the matching Keep-a-Changelog bullet (`### Added` / `### Changed` / `### Fixed` / `### Removed`) in place; otherwise insert a new section at the top under the `# Changelog` heading. One short, high-level, user-facing bullet per theme — never one bullet per edit. If CHANGELOG.md exceeds 200 lines after the edit, trim the oldest sections at the bottom to bring it near 150 lines.
6. Inside `__REPO__/`: `git add -A`, commit, and `git push origin __BRANCH__`. Use the host gitconfig — never pass `--author` or `-c user.email`.
7. Inside `__PARENT__/`: `git add seedkit`, commit `chore: bump seedkit/ — <one-line reason>`, push. Skip steps 6–7 if no edits were made.
8. `rm` the log file at LOGPATH (it's gitignored — plain `rm`, not `git rm`).
9. Final line: `[<log basename>] <one sentence outcome>`.

Hard constraints:
- Don't run `./run-tests.sh` or otherwise spawn a build.
- Don't invoke any skill.
- Don't commit unrelated files. If `git status` shows drift you didn't introduce, stop and report.
- Keep every edit short.
EOF
TODAY_VER=$(date +%y.%V.%u)
WORKSPACE_DEFAULT="$PARENT/seedkit-examples"
WORKSPACE_DIR="${WORKSPACE:-$WORKSPACE_DEFAULT}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE//__TODAY__/$TODAY_VER}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE//__REPO__/$REPO}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE//__PARENT__/$PARENT}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE//__WORKSPACE__/$WORKSPACE_DIR}"
PROMPT_TEMPLATE="${PROMPT_TEMPLATE//__BRANCH__/$CURRENT_BRANCH}"

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

echo
echo "done."
