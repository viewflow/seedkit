#!/usr/bin/env bash
#
# Run seedkit testcases in two isolated phases:
#
#   1. Build  — the agent receives `## Prompt` + `## Boot check` from the
#               testcase. It scaffolds the project and runs runtime smokes
#               (boots the server, hits an endpoint). Auto-fixes are
#               expected when a smoke fails. Build CLI is pluggable
#               (claude or gemini) via $BUILD_CLI.
#   2. Review — always `claude -p`, regardless of which CLI built it.
#               Reads the generated tree against the testcase's
#               `## Review` section. Read-only tools, no skill access, no
#               awareness of how the build went. File existence and
#               content assertions live here so the build context can't
#               game them.
#
# Both phases stream into the same per-case log file. There is no separate
# summary — the per-case logs are the record.
#
# Usage:
#   ./run-tests.sh                          # run all testcases (claude build)
#   ./run-tests.sh 02 07                    # run specific ones
#   MODEL=claude-opus-4-7 ./run-tests.sh    # override build model
#   BUILD_CLI=gemini ./run-tests.sh         # build with gemini, review with claude
#   BUILD_CLI=gemini MODEL=gemini-2.5-pro ./run-tests.sh
#
# Requires: claude CLI (always), gemini CLI (when BUILD_CLI=gemini), jq, python3.

set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TESTCASES="$REPO/testcases"
# Generated projects land in the sibling `seedkit-examples` submodule of
# the parent repo. Logs live under `seedkit-examples/logs/` (gitignored
# inside the examples repo). Override via $WORKSPACE.
WORKSPACE="${WORKSPACE:-$REPO/../seedkit-examples}"
WORKSPACE="$(cd "$WORKSPACE" && pwd)"
LOGS="$WORKSPACE/logs"
BUILD_CLI="${BUILD_CLI:-claude}"
case "$BUILD_CLI" in
    claude) DEFAULT_BUILD_MODEL="claude-sonnet-4-6" ;;
    gemini) DEFAULT_BUILD_MODEL="gemini-2.5-flash" ;;
    *) echo "BUILD_CLI must be 'claude' or 'gemini' (got: $BUILD_CLI)" >&2; exit 1 ;;
esac
MODEL="${MODEL:-$DEFAULT_BUILD_MODEL}"
REVIEW_MODEL="${REVIEW_MODEL:-claude-opus-4-7}"
# Hard ceiling per phase. The build phase occasionally improvises a bash
# command that orphans a forking child tree under PID 1; bash's `wait`
# then blocks forever. setsid + watchdog + post-phase pgrp sweep below
# clean that up.
TIMEOUT_PER_PHASE="${TIMEOUT_PER_PHASE:-7200}"
STAMP="$(date +%Y%m%d-%H%M%S)"

command -v claude  >/dev/null || { echo "claude CLI not found in PATH"; exit 1; }
command -v jq      >/dev/null || { echo "jq not found in PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found in PATH"; exit 1; }
if [[ "$BUILD_CLI" == "gemini" ]]; then
    command -v gemini >/dev/null || { echo "gemini CLI not found in PATH"; exit 1; }
fi

# Keep the Mac awake while we run (macOS only; no-op elsewhere). The
# `-w $$` ties caffeinate to this shell, so it exits with the script.
if command -v caffeinate >/dev/null; then
    caffeinate -i -w $$ &
fi

mkdir -p "$LOGS"

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

cleanup_testcase() {
    # Remove the generated project dir(s) for a single testcase. The
    # project name set inside the testcase doesn't always match the
    # testcase filename (e.g. `01-blog.md` → `01-minimal-blog/`), so
    # match by the leading `NN-` numeric prefix shared by both. Leaves
    # siblings, logs, and examples-repo metadata untouched so a partial
    # run (`./run-tests.sh 02`) doesn't nuke unrelated outputs.
    local tc_name=$1 prefix
    [[ -n "$tc_name" ]] || return 0
    prefix="${tc_name%%-*}-"   # `02-shop` → `02-`
    shopt -s nullglob
    local match
    for match in "$WORKSPACE/$prefix"*/; do
        [[ -d "$match" ]] && rm -rf "$match"
    done
    shopt -u nullglob
}

# Extract the body of a `## <name>` section from a testcase file. Stops
# at the next `## ` heading or EOF. The heading line itself is dropped.
extract_section() {
    local file=$1 section=$2
    awk -v want="$section" '
        /^## / {
            if (in_section) exit
            sub(/^##[[:space:]]+/, "")
            sub(/[[:space:]]+$/, "")
            in_section = ($0 == want)
            next
        }
        in_section { print }
    ' "$file"
}

# Extract the fenced block under "## Prompt" — the literal /seedkit
# invocation, used to prepend to the generated project's README.
extract_prompt_block() {
    awk '
        /^## Prompt[[:space:]]*$/ { in_prompt = 1; next }
        in_prompt && /^```/        { fence_count++; if (fence_count == 2) exit; next }
        in_prompt && fence_count == 1 { print }
    ' "$1"
}

prepend_prompt_to_readme() {
    local project_dir=$1 tc=$2
    local readme="$project_dir/README.md"
    [[ -d "$project_dir" ]] || return 0
    local prompt
    prompt=$(extract_prompt_block "$tc")
    [[ -n "$prompt" ]] || return 0
    local existing=""
    [[ -f "$readme" ]] && existing=$(cat "$readme")
    {
        echo "## Prompt"
        echo
        echo '```'
        echo "$prompt"
        echo '```'
        echo
        if [[ -n "$existing" ]]; then
            echo "---"
            echo
            echo "$existing"
        fi
    } > "$readme"
}

# Portable setsid via Python — macOS ships no `setsid` binary.
setsid_exec() {
    exec python3 -c '
import os, sys
os.setsid()
os.execvp(sys.argv[1], sys.argv[1:])
' "$@"
}

link_skill() {
    # Project-scoped skill so claude -p in $WORKSPACE finds it.
    mkdir -p "$WORKSPACE/.claude/skills"
    ln -snf "$REPO/skills/seedkit-slim" "$WORKSPACE/.claude/skills/seedkit-slim"

    # Gemini uses `gemini skills link` rather than a bare symlink — its
    # discovery mechanism reads the registry, not the directory. Idempotent;
    # re-linking the same path is a no-op.
    if [[ "$BUILD_CLI" == "gemini" ]]; then
        (cd "$WORKSPACE" && gemini skills link "$REPO/skills/seedkit-slim" \
            --scope workspace --consent >/dev/null 2>&1) || true
    fi
}

# Run a single agent invocation in its own session, with a watchdog and
# a post-phase pgrp sweep. Streams text deltas to $log_target, returns
# the CLI's exit code. Caller passes the prompt on stdin.
#
# $cli selects the build agent: `claude` or `gemini`. Review phase
# always passes `claude` since the read-only Bash() tool allowlist is
# claude-specific. Stream-JSON schemas differ between the two — claude
# emits `.event.delta.type == "text_delta"` envelopes; gemini emits flat
# `{type:"message", role:"assistant", delta:true, content:"..."}` rows.
run_phase() {
    local label=$1 cli=$2 model=$3 cwd=$4 log_target=$5 allowed_tools=$6
    local prompt
    prompt=$(cat)

    # Phase header in the log.
    {
        echo
        echo "════════ $label ($cli / $model) ════════"
        echo
    } >> "$log_target"

    pushd "$cwd" >/dev/null

    # Gemini-specific prompt rewrites, done out here so the quoting in
    # the `bash -c` block below stays simple. See the comment above the
    # gemini branch for the rationale.
    if [[ "$cli" == "gemini" ]]; then
        prompt=$(printf '%s' "$prompt" \
            | sed 's|^/seedkit-slim$|Use the seedkit-slim skill to scaffold the project per the questionnaire below.|')
        prompt="Shell-tool note: your run_shell_command runs each call synchronously and does not preserve & backgrounding across calls. When the smoke / deploy snippet uses &, jobs -p, or wait, run the whole snippet inside a single \"timeout 60 bash -c '...'\" invocation so it executes in one child shell and self-terminates.

$prompt"
    fi

    PROMPT="$prompt" CASE_LOG="$log_target" CASE_MODEL="$model" \
    CASE_TOOLS="$allowed_tools" CASE_CLI="$cli" \
    setsid_exec bash -c '
        case "$CASE_CLI" in
            claude)
                if [[ -n "$CASE_TOOLS" ]]; then
                    claude -p "$PROMPT" \
                        --dangerously-skip-permissions \
                        --model="$CASE_MODEL" \
                        --allowedTools "$CASE_TOOLS" \
                        --output-format stream-json \
                        --include-partial-messages \
                        --print \
                        --verbose
                else
                    claude -p "$PROMPT" \
                        --dangerously-skip-permissions \
                        --model="$CASE_MODEL" \
                        --output-format stream-json \
                        --include-partial-messages \
                        --print \
                        --verbose
                fi \
                | jq --unbuffered -j -r '\''select(.event.delta.type? == "text_delta") | .event.delta.text'\'' \
                | tee -a "$CASE_LOG"
                exit "${PIPESTATUS[0]}"
                ;;
            gemini)
                # --skip-trust required for non-interactive headless runs
                # outside trusted folders. --yolo is the gemini analogue
                # of claude'\''s --dangerously-skip-permissions. Prompt was
                # rewritten in the outer shell (slash-command + shell-tool
                # note) before being placed in $PROMPT.
                gemini -p "$PROMPT" \
                    --yolo \
                    --skip-trust \
                    --model "$CASE_MODEL" \
                    --output-format stream-json \
                | jq --unbuffered -j -r '\''
                    if .type == "message" and .role == "assistant" and (.delta // false) then .content
                    elif .type == "tool_use" then "\n[tool:\(.tool_name)] \(.parameters.command // .parameters.file_path // (.parameters | tostring))\n"
                    elif .type == "tool_result" then "[result:\(.status // "?")]\n"
                    else empty end
                  '\'' \
                | tee -a "$CASE_LOG"
                exit "${PIPESTATUS[0]}"
                ;;
            *)
                echo "unknown CLI: $CASE_CLI" >&2
                exit 2
                ;;
        esac
    ' &
    local phase_pid=$! phase_pgid
    phase_pgid=$phase_pid

    (
        sleep "$TIMEOUT_PER_PHASE"
        if kill -0 "$phase_pid" 2>/dev/null; then
            echo >&2
            echo "[run-tests] $label exceeded ${TIMEOUT_PER_PHASE}s — killing pgrp $phase_pgid" >&2
            kill -TERM -- -"$phase_pgid" 2>/dev/null || true
            sleep 5
            kill -KILL -- -"$phase_pgid" 2>/dev/null || true
        fi
    ) &
    local watchdog=$!

    wait "$phase_pid"
    local rc=$?

    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true

    # Sweep orphans (celery, gunicorn, runserver autoreloader).
    kill -TERM -- -"$phase_pgid" 2>/dev/null || true
    sleep 1
    kill -KILL -- -"$phase_pgid" 2>/dev/null || true

    popd >/dev/null
    return "$rc"
}

link_skill

for tc in "${FILES[@]}"; do
    name=$(basename "$tc" .md)
    log="$LOGS/$name-$STAMP.log"
    echo
    echo "==> $name"
    echo "    log:    $log"
    echo "    case:   $tc"

    cleanup_testcase "$name"
    : > "$log"

    # Marker so the project dir created during this case is identifiable
    # (the agent picks the dir name from its prompt; we don't know it
    # ahead of time).
    marker="$LOGS/.start-$name-$STAMP"
    touch "$marker"

    start=$(date +%s)

    # ── Phase 1: build ───────────────────────────────────────────────
    prompt_section=$(extract_section "$tc" "Prompt")
    boot_section=$(extract_section "$tc" "Boot check")
    deploy_section=$(extract_section "$tc" "Deploy check")
    {
        printf '%s\n\n' "$prompt_section"
        if [[ -n "$boot_section" ]]; then
            printf 'After scaffolding completes, run these runtime smoke checks. Auto-fix any failure (the goal is a project that boots and the smoke pipeline returns clean):\n\n'
            printf '%s\n\n' "$boot_section"
            printf 'Wait-for-services rules — observed pitfalls that have hung past runs:\n'
            printf -- '- Use `docker compose up -d --wait` (or `--wait-timeout 60`) when the smoke depends on services being up. It blocks on the compose-side healthchecks and exits non-zero on failure. Don'\''t hand-roll a polling loop.\n'
            printf -- '- Never pipe `docker compose ps --format json` into `json.load` — Compose v2.6+ emits newline-delimited JSON, not an array. `json.load` reads the whole stream and raises, your loop stays at exit 1, and the bash tool livelocks.\n'
            printf -- '- If a service has no healthcheck declared, add one in `docker-compose.yml` rather than polling externally.\n'
            printf -- '- Kill background servers with `kill -- -"$SERVER_PID" 2>/dev/null; wait` (negative PID = send to whole process group). Plain `kill $PID` or `kill $(jobs -p)` only terminates the launcher (`uv run`), leaving the Python grandchild alive; `wait` then blocks until it exits on its own.\n\n'
        fi
        if [[ -n "$deploy_section" ]]; then
            printf 'Then exercise the **production artifact** end-to-end. This catches what the dev-mode boot can'\''t: missing prod deps, DEBUG=False breakage, `migrate --check` drift, `collectstatic` failures, missing security headers. Auto-fix any failure:\n\n'
            printf '%s\n\n' "$deploy_section"
            printf 'Deploy-smoke rules:\n'
            printf -- '- Run gunicorn from the built prod image — never `runserver` against production settings.\n'
            printf -- '- Always tear down the smoke containers, network, and volumes at the end (even on failure) — orphaned `postgres:17` containers from a previous run will collide on the next.\n'
            printf -- '- Before tearing down, assert no anonymous volumes were created: `! docker compose ps -q | xargs docker inspect --format '"'"'{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}'"'"' 2>/dev/null | grep -qE '"'"'^[0-9a-f]{64}$'"'"'`. Anonymous volumes (64-char hex names) mean a `VOLUME` declaration in the Dockerfile has no named counterpart in `docker-compose.yml` — they litter the host and survive `docker compose down`.\n\n'
        fi
        printf 'At the end, summarise: What worked out of the box / What broke / Fixes applied / Suggested skill changes.\n'
    } | run_phase "BUILD" "$BUILD_CLI" "$MODEL" "$WORKSPACE" "$log" ""
    build_rc=$?

    # Locate the generated project: any subdir with files newer than the
    # marker, excluding the logs dir.
    project_dir=$(find "$WORKSPACE" -mindepth 1 -maxdepth 1 -type d \
        -not -name 'logs' -not -name '.claude' -not -name '.git' \
        -newer "$marker" 2>/dev/null | head -1)
    rm -f "$marker"

    # Prepend the testcase prompt to the project's README.
    if [[ -n "$project_dir" ]]; then
        prepend_prompt_to_readme "$project_dir" "$tc"
    fi

    # ── Phase 2: review ──────────────────────────────────────────────
    review_section=$(extract_section "$tc" "Review")
    review_rc=0
    if [[ -n "$review_section" && -n "$project_dir" ]]; then
        printf '%s\n' "$review_section" \
            | run_phase "REVIEW" "claude" "$REVIEW_MODEL" "$project_dir" "$log" \
                "Read,Grep,Glob,Bash(ls:*),Bash(cat:*),Bash(rg:*),Bash(find:*)"
        review_rc=$?
    fi

    end=$(date +%s)
    duration=$((end - start))
    {
        echo
        echo "════════ DONE ════════"
        printf '[build_exit: %s, review_exit: %s, duration: %ss]\n' "$build_rc" "$review_rc" "$duration"
    } >> "$log"
done

# Top-level README for the examples collection.
{
    echo "# seedkit-examples"
    echo
    echo "Reference Django projects scaffolded by the [seedkit](https://github.com/RobustaRush/seedkit) skill, paired with the prompts that produced them."
    echo
    echo "Each subdirectory is a fresh project generated end-to-end by \`claude -p\` running the matching testcase from \`seedkit/testcases/\`. The first section of every project's \`README.md\` is the verbatim \`/seedkit\` prompt — answers to every Foundation / add-on / production question — so the exact configuration is reproducible."
    echo
    echo "## Projects"
    echo
    for sub in "$WORKSPACE"/*/; do
        sub_name=$(basename "$sub")
        [[ "$sub_name" == "logs" ]] && continue
        [[ -f "$sub/README.md" ]] || continue
        purpose=$(awk '
            /^Purpose: / { sub(/^Purpose: */, ""); print; exit }
        ' "$sub/README.md" 2>/dev/null)
        if [[ -n "$purpose" ]]; then
            echo "- [\`$sub_name/\`]($sub_name/) — $purpose"
        else
            echo "- [\`$sub_name/\`]($sub_name/)"
        fi
    done
    echo
    echo "## Reproducing"
    echo
    echo "From the parent repo:"
    echo
    echo '```sh'
    echo "cd seedkit"
    echo "./run-tests.sh                  # all cases"
    echo "./run-tests.sh 02 07            # specific cases"
    echo '```'
    echo
    echo "Output lands directly here. Per-run logs (build phase + review phase) live in \`logs/\`."
} > "$WORKSPACE/README.md"

echo
echo "Logs:  $LOGS/"
echo "Index: $WORKSPACE/README.md"
