#!/usr/bin/env bash
# Enforces the documentation rules from the root CLAUDE.md.
#
# Three checks, deliberately layered — each catches what the previous cannot:
#
#   A. same-change   Code changed in a folder => that folder's CLAUDE.md changed
#                    in the same set. Also: project.godot changed => the root
#                    CLAUDE.md changed. Catches "wrote code, forgot the doc".
#
#   B. code map      Every folder holding code is linked from the root
#                    CLAUDE.md's code map, and every doc the map links exists.
#                    Catches a new folder appearing without the root noticing —
#                    the root doc's only volatile claim, made checkable.
#
#   C. verification  Every folder doc carries a `verified-against: <sha>` stamp,
#                    and no commit since that sha touched the folder without
#                    also touching the doc. Catches everything that bypasses A:
#                    history predating these hooks, merge-conflict resolutions,
#                    web edits, and contributors running without hooks.
#
# A commit that changes both a folder's files and its doc satisfies C on its
# own, so the stamp never needs bumping for well-formed work. Re-stamping is
# the remedy for clearing debt, not routine bookkeeping.
#
# Modes:
#   (no args)         Claude Code Stop hook — working tree + history
#   --diff <range>    CI on a pull request — the range + history
#   --audit           History only; no working-tree or range checks
set -u
cd "$(git rev-parse --show-toplevel)" || exit 0

ROOT_DOC='CLAUDE.md'
CODE_RE='\.(gd|gdshader|tscn)$'

changed=''
run_same_change=1

case "${1:-}" in
  --diff)
    range="${2:?usage: check-folder-docs.sh --diff <range>}"
    changed=$(git diff --name-only --no-renames "$range")
    ;;
  --audit)
    run_same_change=0
    ;;
  '')
    # Stop hook: stdin carries the hook JSON. If we already blocked once this
    # turn, let the stop through rather than looping forever.
    input=$(cat 2>/dev/null || true)
    case "$input" in
      *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
    esac
    changed=$(git status --porcelain -uall | cut -c4- | sed 's/.* -> //')
    ;;
  *)
    echo "usage: check-folder-docs.sh [--diff <range> | --audit]" >&2
    exit 64
    ;;
esac

# Folder docs, root excluded — the root is the project guide, not a folder doc.
folder_docs() {
  git ls-files -- '*/CLAUDE.md' | sort
}

# Folders holding code, from tracked files plus anything new on disk.
code_dirs() {
  git ls-files -c -o --exclude-standard -- '*.gd' '*.gdshader' '*.tscn' \
    | while IFS= read -r f; do dirname "$f"; done \
    | sort -u
}

# --- A. same-change ----------------------------------------------------------
check_same_change() {
  [ "$run_same_change" = 1 ] || return 0
  [ -n "$changed" ] || return 0

  printf '%s\n' "$changed" | grep -E "$CODE_RE" \
    | while IFS= read -r f; do dirname "$f"; done \
    | sort -u \
    | while IFS= read -r d; do
        [ -n "$d" ] && [ "$d" != '.' ] || continue
        [ -d "$d" ] || continue          # folder deleted outright
        doc="$d/CLAUDE.md"
        if [ ! -f "$doc" ]; then
          echo "MISSING     $doc"
          echo "            code changed in $d/ but the folder has no CLAUDE.md"
        elif ! printf '%s\n' "$changed" | grep -qxF "$doc"; then
          echo "UNTOUCHED   $doc"
          echo "            code changed in $d/ but its CLAUDE.md did not"
        fi
      done

  if printf '%s\n' "$changed" | grep -qxF 'project.godot' \
     && ! printf '%s\n' "$changed" | grep -qxF "$ROOT_DOC"; then
    echo "UNTOUCHED   $ROOT_DOC"
    echo "            project.godot changed but the root CLAUDE.md did not"
  fi
}

# --- B. code map -------------------------------------------------------------
check_code_map() {
  [ -f "$ROOT_DOC" ] || return 0

  code_dirs | while IFS= read -r d; do
    [ -n "$d" ] && [ "$d" != '.' ] || continue
    grep -qF "$d/CLAUDE.md" "$ROOT_DOC" || {
      echo "UNLISTED    $d/"
      echo "            holds code but is not linked from the code map in $ROOT_DOC"
    }
  done

  grep -oE '[A-Za-z0-9_./-]+/CLAUDE\.md' "$ROOT_DOC" | sort -u \
    | while IFS= read -r doc; do
        [ -f "$doc" ] || {
          echo "DANGLING    $doc"
          echo "            linked from $ROOT_DOC but no such file exists"
        }
      done
}

# --- C. verification ---------------------------------------------------------
# Commits since <stamp> that changed files directly in <dir> without touching
# <dir>/CLAUDE.md. Files in nested subfolders belong to their own doc.
unaccompanied_commits() {
  d="$1"
  stamp="$2"
  git rev-list --no-merges "${stamp}..HEAD" -- "$d" | while IFS= read -r c; do
    files=$(git show --pretty=format: --name-only "$c" -- "$d")
    direct=$(printf '%s\n' "$files" | while IFS= read -r f; do
      [ -n "$f" ] || continue
      [ "$(dirname "$f")" = "$d" ] || continue
      [ "$f" = "$d/CLAUDE.md" ] && continue
      printf '%s\n' "$f"
    done)
    [ -n "$direct" ] || continue
    printf '%s\n' "$files" | grep -qxF "$d/CLAUDE.md" \
      || git log -1 --format='%h %s' "$c"
  done
}

check_verification() {
  folder_docs | while IFS= read -r doc; do
    d=$(dirname "$doc")
    stamp=$(sed -n 's/.*verified-against:[[:space:]]*\([0-9a-fA-F]\{7,40\}\).*/\1/p' "$doc" | head -1)

    if [ -z "$stamp" ]; then
      echo "NOSTAMP     $doc"
      echo "            no '<!-- verified-against: <sha> -->' marker"
      continue
    fi
    if ! git rev-parse --verify --quiet "${stamp}^{commit}" >/dev/null 2>&1; then
      echo "BADSTAMP    $doc"
      echo "            verified-against: $stamp is not a commit in this repository"
      continue
    fi

    offenders=$(unaccompanied_commits "$d" "$stamp")
    [ -n "$offenders" ] || continue
    echo "UNVERIFIED  $doc"
    echo "            $d/ changed since $stamp without the doc being updated:"
    printf '%s\n' "$offenders" | sed 's/^/              /'
  done
}

problems=$(
  check_same_change
  check_code_map
  check_verification
)

[ -z "$problems" ] && exit 0

{
  echo "Documentation check failed — see 'Per-folder context docs' in $ROOT_DOC."
  echo ''
  echo "$problems"
  echo ''
  echo "MISSING     create the folder's CLAUDE.md: what this part of the game does,"
  echo "            its key scenes/scripts, signals, and cross-folder dependencies."
  echo "UNTOUCHED   re-read the doc against the change and update it. If it is"
  echo "            genuinely still accurate, say so and stop again rather than"
  echo "            making a no-op edit to silence this."
  echo "UNLISTED    the root CLAUDE.md's code map is the one inventory it keeps;"
  echo "DANGLING    add the row, or drop it if the folder is gone."
  echo "NOSTAMP     append to the doc:  <!-- verified-against: \$(git rev-parse --short HEAD) -->"
  echo "UNVERIFIED  read the listed commits against the doc, correct whatever no"
  echo "            longer holds, then bump the stamp to the current HEAD. Bump it"
  echo "            only once the doc is actually true — the stamp is a claim that"
  echo "            someone checked, and it is the only such claim in the repo."
} >&2
exit 2
