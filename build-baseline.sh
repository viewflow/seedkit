#!/usr/bin/env bash
#
# Snapshot each generated project under seedkit-examples/ as a manifest
# JSON. Baselines live in seedkit-examples/baselines/<branch>/<case>.json
# so the same repo holds baselines for both `main` (seedkit) and
# `train-seedkit-slim` (seedkit-slim).
#
# Manual invocation — not wired into run-tests.sh / review-logs.sh. Run
# after a clean regeneration to update the reference set:
#
#   ./build-baseline.sh                 # all NN-* case dirs
#   ./build-baseline.sh 02-shop         # one case (by dir name)
#
# Each manifest captures: skill version, branch, case dir, generated
# date, and a sorted list of (path, size, sha256) for every tracked
# file. Excludes .venv, .git, __pycache__, node_modules, *.pyc, db.sqlite3,
# media/, staticfiles/ — everything regeneration would clobber anyway.

set -uo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
PARENT="$(cd "$REPO/.." && pwd)"
WORKSPACE="${WORKSPACE:-$PARENT/seedkit-examples}"
WORKSPACE="$(cd "$WORKSPACE" && pwd)"

command -v jq      >/dev/null || { echo "jq not found in PATH"; exit 1; }
command -v python3 >/dev/null || { echo "python3 not found in PATH"; exit 1; }

BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
SKILL_DIR="skills/seedkit"
[[ "$BRANCH" == "train-seedkit-slim" ]] && SKILL_DIR="skills/seedkit-slim"

SKILL_VERSION="$(awk -F': *' '/^version:/ {print $2; exit}' "$REPO/$SKILL_DIR/SKILL.md" 2>/dev/null || echo unknown)"

OUT_DIR="$WORKSPACE/baselines/$BRANCH"
mkdir -p "$OUT_DIR"

shopt -s nullglob
declare -a CASES=()
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        if [[ -d "$WORKSPACE/$arg" ]]; then
            CASES+=("$WORKSPACE/$arg")
        else
            echo "skip: $arg not found under $WORKSPACE" >&2
        fi
    done
else
    for d in "$WORKSPACE"/[0-9][0-9]-*/; do
        CASES+=("${d%/}")
    done
fi

if [[ ${#CASES[@]} -eq 0 ]]; then
    echo "no case dirs to snapshot under $WORKSPACE"
    exit 0
fi

echo "branch:        $BRANCH"
echo "skill version: $SKILL_VERSION"
echo "output:        $OUT_DIR"
echo

# Emit one manifest per case dir. Walk the tree, skip noise, hash each
# file. Python keeps this portable across mac/linux without depending on
# coreutils sha256sum vs shasum.
for case_dir in "${CASES[@]}"; do
    case_name="$(basename "$case_dir")"
    out_file="$OUT_DIR/$case_name.json"
    echo "==> $case_name"

    python3 - "$case_dir" "$case_name" "$BRANCH" "$SKILL_VERSION" "$out_file" <<'PY'
import hashlib, json, os, sys, datetime, pathlib

case_dir, case_name, branch, version, out_file = sys.argv[1:6]
case_path = pathlib.Path(case_dir)

EXCLUDE_DIRS = {
    ".git", ".venv", "venv", "__pycache__", "node_modules",
    "staticfiles", "media", ".mypy_cache", ".pytest_cache",
    ".ruff_cache", "logs", ".django_tailwind_cli", ".devcontainer-data",
}
EXCLUDE_SUFFIX = (".pyc", ".pyo", ".sqlite3", ".sqlite3-journal", ".log")
MAX_BYTES = 1_000_000  # baselines track config/source; skip downloaded binaries

files = []
skipped_large = []
for root, dirs, fnames in os.walk(case_path):
    dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
    for fname in fnames:
        if fname.endswith(EXCLUDE_SUFFIX):
            continue
        full = pathlib.Path(root) / fname
        if not full.is_file():
            continue
        rel = full.relative_to(case_path).as_posix()
        size = full.stat().st_size
        if size > MAX_BYTES:
            skipped_large.append({"path": rel, "size": size})
            continue
        data = full.read_bytes()
        files.append({
            "path": rel,
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        })

files.sort(key=lambda f: f["path"])
skipped_large.sort(key=lambda f: f["path"])

manifest = {
    "case": case_name,
    "branch": branch,
    "skill_version": version,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "file_count": len(files),
    "total_bytes": sum(f["size"] for f in files),
    "skipped_large": skipped_large,
    "files": files,
}

pathlib.Path(out_file).write_text(json.dumps(manifest, indent=2) + "\n")
print(f"    {len(files):4d} files, {manifest['total_bytes']:>9} bytes -> {out_file}"
      + (f"  (skipped {len(skipped_large)} >1MB)" if skipped_large else ""))
PY
done

echo
echo "done. ${#CASES[@]} manifest(s) written under $OUT_DIR"
echo "commit them in seedkit-examples/ when satisfied:"
echo "    cd $WORKSPACE && git add baselines/$BRANCH && git commit -m 'baseline: $BRANCH @ $SKILL_VERSION' && git push"
