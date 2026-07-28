#!/usr/bin/env bash
# Enforces the per-folder CLAUDE.md rule from the root CLAUDE.md:
# every folder with changed code files (.gd, .gdshader, .tscn) must have a
# CLAUDE.md that was created/updated alongside the code change.
#
# Modes:
#   (no args)         Claude Code Stop hook: checks uncommitted changes
#   --diff <range>    CI: checks files changed in the given git range
set -u
cd "$(git rev-parse --show-toplevel)" || exit 0

CODE_RE='\.(gd|gdshader|tscn)$'

if [ "${1:-}" = "--diff" ]; then
  range="${2:?usage: check-folder-docs.sh --diff <range>}"
  changed=$(git diff --name-only --no-renames "$range")
else
  # Hook mode: stdin carries the hook JSON. If we already blocked once this
  # turn (stop_hook_active), let the stop through to avoid an infinite loop.
  input=$(cat 2>/dev/null || true)
  case "$input" in
    *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
  esac
  changed=$(git status --porcelain -uall | cut -c4- | sed 's/.* -> //')
fi

code_files=$(printf '%s\n' "$changed" | grep -E "$CODE_RE" || true)
[ -z "$code_files" ] && exit 0

dirs=$(printf '%s\n' "$code_files" | while IFS= read -r f; do dirname "$f"; done | sort -u)

problems=$(printf '%s\n' "$dirs" | while IFS= read -r d; do
  [ "$d" = "." ] && continue   # root CLAUDE.md is the project guide, not a folder doc
  [ -d "$d" ] || continue      # folder was deleted entirely
  doc="$d/CLAUDE.md"
  if [ ! -f "$doc" ]; then
    echo "MISSING: $doc — code changed in $d/ but the folder has no CLAUDE.md"
  elif ! printf '%s\n' "$changed" | grep -qxF "$doc"; then
    echo "STALE: $doc — code changed in $d/ but its CLAUDE.md was not touched"
  fi
done)

[ -z "$problems" ] && exit 0

{
  echo "Per-folder documentation check failed (see 'Per-folder context docs' in the root CLAUDE.md):"
  echo "$problems"
  echo ""
  echo "MISSING: create that folder's CLAUDE.md describing what the folder does,"
  echo "its key scenes/scripts, signals, and dependencies."
  echo "STALE: re-read the doc against the code changes and update it. If it is"
  echo "genuinely still accurate, make a trivial confirming touch unnecessary by"
  echo "stating that briefly and stopping again."
} >&2
exit 2
