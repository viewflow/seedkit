#!/usr/bin/env bash
#
# Run seedkit testcases through `claude -p` in two isolated phases:
#
#   1. Build  — the agent receives `## Prompt` + `## Boot check` from the
#               testcase. It scaffolds the project and runs runtime smokes
#               (boots the server, hits an endpoint). Auto-fixes are
#               expected when a smoke fails.
#   2. Review — a fresh `claude -p` reads the generated tree against the
#               testcase's `## Review` section. Read-only tools, no skill
#               access, no awareness of how the build went. File existence
#               and content assertions live here so the build context can't
#               game them.
#
# Both phases stream into the same per-case log file. There is no separate
# summary — the per-case logs are the record.
#
# Usage:
#   ./run-tests.sh                          # run all testcases
#   ./run-tests.sh 02 07                    # run specific ones
#   MODEL=claude-opus-4-7 ./run-tests.sh    # override build model
#
# Requires: claude CLI, jq, python3.

set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TESTCASES="$REPO/testcases"
# Generated projects land in the sibling `seedkit-examples` submodule of
# the parent repo. Logs live under `seedkit-examples/logs/` (gitignored
# inside the examples repo). Override via $WORKSPACE.
WORKSPACE="${WORKSPACE:-$REPO/../seedkit-examples}"
WORKSPACE="$(cd "$WORKSPACE" && pwd)"
LOGS="$WORKSPACE/logs"
MODEL="${MODEL:-claude-sonnet-4-6}"
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

cleanup_workspace() {
    # Remove generated projects but preserve the examples-repo metadata
    # (`.git`, `.gitignore`, top-level `README.md` regenerated at the end
    # of the run) and the logs dir.
    find "$WORKSPACE" -mindepth 1 -maxdepth 1 \
        ! -name '.git' \
        ! -name '.gitignore' \
        ! -name '.gitattributes' \
        ! -name 'LICENSE' \
        ! -name 'README.md' \
        ! -name 'logs' \
        -exec rm -rf {} +
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
    ln -snf "$REPO/skills/seedkit" "$WORKSPACE/.claude/skills/seedkit"
}

# Run a single claude -p invocation in its own session, with a watchdog
# and a post-phase pgrp sweep. Streams text deltas to $log_target,
# returns claude's exit code. Caller passes the prompt on stdin.
run_phase() {
    local label=$1 model=$2 cwd=$3 log_target=$4 allowed_tools=$5
    local prompt
    prompt=$(cat)

    # Phase header in the log.
    {
        echo
        echo "════════ $label ════════"
        echo
    } >> "$log_target"

    pushd "$cwd" >/dev/null

    PROMPT="$prompt" CASE_LOG="$log_target" CASE_MODEL="$model" \
    CASE_TOOLS="$allowed_tools" \
    setsid_exec bash -c '
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

cleanup_workspace
link_skill

for tc in "${FILES[@]}"; do
    name=$(basename "$tc" .md)
    log="$LOGS/$name-$STAMP.log"
    echo
    echo "==> $name"
    echo "    log:    $log"
    echo "    case:   $tc"

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
    {
        printf '%s\n\n' "$prompt_section"
        if [[ -n "$boot_section" ]]; then
            printf 'After scaffolding completes, run these runtime smoke checks. Auto-fix any failure (the goal is a project that boots and the smoke pipeline returns clean):\n\n'
            printf '%s\n\n' "$boot_section"
        fi
        printf 'At the end, summarise: What worked out of the box / What broke / Fixes applied / Suggested skill changes.\n'
    } | run_phase "BUILD" "$MODEL" "$WORKSPACE" "$log" ""
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
            | run_phase "REVIEW" "$REVIEW_MODEL" "$project_dir" "$log" \
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
