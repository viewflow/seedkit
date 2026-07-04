#!/usr/bin/env bash
#
# Shared agent-CLI plumbing for seedkit's harness scripts (run-tests.sh,
# run-baseline.sh, review-logs.sh). Source this file — it defines
# functions only, no top-level side effects.
#
# Supported CLIs: claude, codex, agy (Google Antigravity).
# Each has its own non-interactive invocation, permission-bypass flag,
# and JSON event schema; cli_dispatch() is the one place that knows
# about all three so the calling scripts don't have to.
#
# What each CLI needed, confirmed by hand against the installed binaries:
#   claude — `-p PROMPT --output-format stream-json`, events are
#            `.event.delta.type == "text_delta"` envelopes.
#   codex  — `exec --json PROMPT`, items arrive whole (not token deltas):
#            `{"type":"item.completed","item":{"type":"agent_message","text":...}}`,
#            `{"type":"item.completed","item":{"type":"command_execution",...}}`.
#   agy    — `--print PROMPT` has no JSON/streaming mode; it prints the
#            final response as plain text once the turn completes.

# Portable setsid via Python — macOS ships no `setsid` binary. Puts the
# exec'd process in its own session/process group so a watchdog can kill
# the whole tree with `kill -- -$pgid`.
setsid_exec() {
    exec python3 -c '
import os, sys
os.setsid()
os.execvp(sys.argv[1], sys.argv[1:])
' "$@"
}

# cli_require <cli> — checks the CLI binary is on PATH.
cli_require() {
    case "$1" in
        claude|codex|agy)
            command -v "$1" >/dev/null || { echo "$1 CLI not found in PATH" >&2; return 1; } ;;
        *)
            echo "unknown CLI: $1 (want: claude, codex, agy)" >&2; return 1 ;;
    esac
}

# run_watched <timeout_seconds> <label> <cmd...>
#
# Runs cmd in the background (cmd must already setsid itself — see
# setsid_exec above — so it's its own process group leader), applies a
# watchdog that TERMs then KILLs the group on timeout, and sweeps
# stragglers (orphaned celery/gunicorn/runserver, a stuck git push) once
# the command exits. Sets $RUN_WATCHED_RC to the command's real exit code.
run_watched() {
    local timeout=$1 label=$2; shift 2
    "$@" &
    local pid=$! pgid=$!

    (
        sleep "$timeout"
        if kill -0 "$pid" 2>/dev/null; then
            echo >&2
            echo "[watchdog] $label exceeded ${timeout}s — killing pgrp $pgid" >&2
            kill -TERM -- -"$pgid" 2>/dev/null || true
            sleep 5
            kill -KILL -- -"$pgid" 2>/dev/null || true
        fi
    ) &
    local watchdog=$!

    wait "$pid"
    RUN_WATCHED_RC=$?

    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true

    kill -TERM -- -"$pgid" 2>/dev/null || true
    sleep 1
    kill -KILL -- -"$pgid" 2>/dev/null || true
}

# extract_section <file> <section-name>
#
# Pulls the body of a `## <name>` markdown section, stopping at the next
# `## ` heading or EOF. The heading line itself is dropped.
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

# cli_dispatch — runs one non-interactive turn on $CASE_CLI and streams
# the result to stdout (and to $CASE_LOG, if set).
#
# Must run inside a fresh `bash -c 'cli_dispatch'` spawned via
# setsid_exec, with `export -f cli_dispatch` done beforehand in the
# parent shell — that's how the function crosses into the exec'd
# process (see run-tests.sh / run-baseline.sh / review-logs.sh for the
# call site). Reads its config from env vars rather than arguments for
# that reason:
#
#   CASE_CLI    claude | codex | agy
#   CASE_MODEL  model id/name; empty means "let the CLI pick its default"
#   PROMPT      the full prompt text
#   CASE_TOOLS  claude-only: --allowedTools value. When set, claude runs
#               in the read-only reviewer mode instead of full-bypass —
#               this is the ONLY per-CLI mode switch in the harness today
#               (every other caller runs CLIs in full-bypass/build mode).
#   CASE_LOG    optional; when set, output is teed there as well as stdout.
#
# Exits with the underlying CLI's real exit code (not jq's — via
# PIPESTATUS), so callers can tell a genuine failure from a clean run.
cli_dispatch() {
    case "$CASE_CLI" in
        claude)
            if [[ -n "${CASE_TOOLS:-}" ]]; then
                claude -p "$PROMPT" --model="$CASE_MODEL" \
                    --allowedTools "$CASE_TOOLS" \
                    --output-format stream-json --include-partial-messages \
                    --print --verbose
            else
                claude -p "$PROMPT" --model="$CASE_MODEL" \
                    --dangerously-skip-permissions \
                    --output-format stream-json --include-partial-messages \
                    --print --verbose
            fi \
            | jq --unbuffered -j -r 'select(.event.delta.type? == "text_delta") | .event.delta.text' \
            | _cli_sink
            exit "${PIPESTATUS[0]}"
            ;;
        codex)
            local -a margs=()
            [[ -n "${CASE_MODEL:-}" ]] && margs=(-m "$CASE_MODEL")
            # --dangerously-bypass-approvals-and-sandbox is codex's
            # analogue of claude's --dangerously-skip-permissions.
            # `< /dev/null` — exec's stdin-append feature ("Reading
            # additional input from stdin...") otherwise waits on a
            # pipe that's already closed by the outer prompt=$(cat).
            codex exec --json --skip-git-repo-check \
                --dangerously-bypass-approvals-and-sandbox \
                "${margs[@]}" "$PROMPT" < /dev/null \
            | jq --unbuffered -j -r '
                if .type == "item.completed" and .item.type == "agent_message" then .item.text + "\n"
                elif .type == "item.completed" and .item.type == "command_execution" then "\n[tool:shell] \(.item.command)\n[result:exit \(.item.exit_code)] \(.item.aggregated_output // "")\n"
                elif .type == "item.completed" and .item.type == "file_change" then "\n[tool:file_change] \(.item.path // (.item | tostring))\n"
                elif .type == "turn.failed" then "\n[error] \(.error.message // (.error | tostring))\n"
                else empty end
              ' \
            | _cli_sink
            exit "${PIPESTATUS[0]}"
            ;;
        agy)
            local -a margs=()
            [[ -n "${CASE_MODEL:-}" ]] && margs=(--model "$CASE_MODEL")
            # No JSON/streaming mode in this CLI (confirmed against the
            # installed binary) — --print blocks until the turn is done,
            # then prints the final response as plain text. So no jq
            # stage: log liveness for agy runs is worse than the other
            # three CLIs until it grows one.
            agy --print --dangerously-skip-permissions "${margs[@]}" "$PROMPT" \
            | _cli_sink
            exit "${PIPESTATUS[0]}"
            ;;
        *)
            echo "unknown CLI: $CASE_CLI" >&2
            exit 2
            ;;
    esac
}

_cli_sink() {
    if [[ -n "${CASE_LOG:-}" ]]; then
        tee -a "$CASE_LOG"
    else
        cat
    fi
}
