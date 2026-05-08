#!/usr/bin/env bash
#
# Run cookiecutter testcases through `claude -p` one at a time.
#
# Each case runs in cookiecutter/workspace/ (gitignored). Workspace is wiped
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
STAMP="$(date +%Y%m%d-%H%M%S)"
SUMMARY="$LOGS/summary-$STAMP.md"

command -v claude >/dev/null || { echo "claude CLI not found in PATH"; exit 1; }
command -v jq     >/dev/null || { echo "jq not found in PATH"; exit 1; }

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

link_skill() {
    # Expose the cookiecutter skill to claude -p as a project-scoped skill.
    # Without this the sub-claude can't find it and falls back to ad-hoc behavior.
    mkdir -p "$WORKSPACE/.claude/skills"
    ln -snf "$REPO/skills/cookiecutter" "$WORKSPACE/.claude/skills/cookiecutter"
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

    start=$(date +%s)
    claude -p "$(cat "$tc")" \
        --dangerously-skip-permissions \
        --model="$MODEL" \
        --output-format stream-json \
        --include-partial-messages \
        --print \
        --verbose \
    | jq --unbuffered -j -r 'select(.event.delta.type? == "text_delta") | .event.delta.text' \
    | tee "$log"
    rc=${PIPESTATUS[0]}
    end=$(date +%s)
    duration=$((end - start))

    {
        printf '\n[exit: %s, duration: %ss]\n' "$rc" "$duration"
    } >> "$log"

    # Try to grab a REVIEW.md the testcase may have written.
    review=$(find "$WORKSPACE" -mindepth 2 -maxdepth 4 -name 'REVIEW.md' -not -path "*/logs/*" 2>/dev/null | head -1)

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
