#!/usr/bin/env bash
# Fails when a change would bloat the repository (issue #13). This is the
# mechanical half of the assets policy in the root CLAUDE.md -- commit only the
# files a scene uses, never whole packs, never archives -- which reviewers
# otherwise enforce by eye. The repo is public and every asset ships in the web
# deploy, so a slip is paid for by every clone and every page load.
#
# Three rules, over the files the range touches:
#   1. no file touched is larger than MAX_FILE_MB at HEAD;
#   2. the range introduces no more than MAX_TOTAL_MB in total -- an added file
#      counts whole, a modified or renamed file counts by how much it grew, and
#      a deletion counts nothing. Net size is deliberately not the measure: a
#      clone never shrinks, because a deleted or replaced blob stays in history;
#   3. no file touched is a .zip/.rar/.7z archive.
#
# The limits are policy, so the root CLAUDE.md names them; the defaults below
# are where they take effect. Change both.
#
# Usage:  BASE=origin/main bash .github/scripts/check-repo-bloat.sh
# build-check.yml runs it before Godot is downloaded, so a bloated PR fails in
# seconds. Run it locally the same way before pushing an asset PR.
set -euo pipefail

base="${BASE:?set BASE to the ref to diff against, e.g. origin/main}"
max_file_mb="${MAX_FILE_MB:-10}"
max_total_mb="${MAX_TOTAL_MB:-20}"
max_file=$((max_file_mb * 1024 * 1024))
max_total=$((max_total_mb * 1024 * 1024))

# Diff from where this branch left the base, not from the base's current tip:
# a file the base changed since then is not this range's doing.
from=$(git merge-base "$base" HEAD)

# Size of a blob at a ref; 0 when the path does not exist there.
blob_size() { git cat-file -s "$1:$2" 2>/dev/null || echo 0; }

mb() { awk -v b="$1" 'BEGIN { printf "%.1f MB", b / 1048576 }'; }

failed=0
introduced=0
touched=0

while IFS=$'\t' read -r status p1 p2; do
  [ -n "${p1:-}" ] || continue
  case "$status" in
    A|M) path=$p1; old=$p1 ;;
    R*)  path=$p2; old=$p1 ;;   # renamed, possibly edited too: grew relative to the old path
    *)   continue ;;
  esac
  touched=$((touched + 1))

  if printf '%s' "$path" | grep -qiE '\.(zip|rar|7z)$'; then
    echo "::error file=$path::archive committed -- unpack it and commit only the files a scene uses"
    failed=1
  fi

  head_size=$(blob_size HEAD "$path")
  if [ "$head_size" -gt "$max_file" ]; then
    echo "::error file=$path::$(mb "$head_size") is over the ${max_file_mb} MB per-file limit"
    failed=1
  fi

  case "$status" in
    A) introduced=$((introduced + head_size)) ;;
    *) grew=$((head_size - $(blob_size "$from" "$old")))
       if [ "$grew" -gt 0 ]; then introduced=$((introduced + grew)); fi ;;
  esac
done < <(git -c core.quotePath=false diff -M --name-status --diff-filter=AMR "$from" HEAD)

if [ "$introduced" -gt "$max_total" ]; then
  echo "::error::this change introduces $(mb "$introduced"), over the ${max_total_mb} MB limit for one PR"
  failed=1
fi

echo "repo bloat check: $touched file(s) touched, $(mb "$introduced") introduced (limits: ${max_file_mb} MB per file, ${max_total_mb} MB per PR)"
if [ "$failed" -ne 0 ]; then
  echo "See 'Assets' in the root CLAUDE.md for the policy this enforces."
  exit 1
fi
