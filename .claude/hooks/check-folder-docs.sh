#!/usr/bin/env bash
# Enforces the documentation rules from the root CLAUDE.md.
#
# Four checks, deliberately layered — each catches what the previous cannot:
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
#   D. dependency    Every folder doc declares `depends-on: [...]` — the folders
#      graph         its own claims rest on — and no doc is left unread after
#                    code in one of those moved. Catches what A–C structurally
#                    cannot: each of them examines a folder alone, so none can
#                    see a doc invalidated from *outside* its own folder.
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
    # Last match, not first: the stamp is the file's trailing marker, and a doc
    # may legitimately discuss the convention above it — .claude/hooks/CLAUDE.md
    # does. Same class of self-reference trap the Flowdex hook hit twice.
    stamp=$(sed -n 's/.*verified-against:[[:space:]]*\([0-9a-fA-F]\{7,40\}\).*/\1/p' "$doc" | tail -1)

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

# --- D. dependency graph -----------------------------------------------------
# Each folder doc declares `depends-on: [a, b]` in YAML frontmatter: the folders
# whose code its own claims rest on. Only this direction is stored — the reverse
# ("what do I affect?") is its inverse, and keeping both would only create two
# records that can disagree.
#
# The check that earns its keep is not shape, it is staleness *across* an edge.
# Check C asks whether a folder changed since its own stamp; D asks whether
# anything it depends on did. That is the drift nothing else catches: change the
# navmesh settings in scenes/ and scenes/map/CLAUDE.md can silently stop being
# true, because its own folder never moved.
# Frontmatter body only: line 2 through the first closing `---`. NOT a
# /^---$/,/^---$/ range — sed restarts a range at every later match, so a
# markdown horizontal rule further down the file reopens it and any prose line
# beginning `depends-on:` is read as a real edge. That is the self-reference
# trap again, in a third form: a doc explaining this convention would be
# misparsed by the parser it explains. Callers check line 1 is `---` first.
declared_deps() {
  sed -n '2,/^---$/p' "$1" \
    | sed -n 's/^depends-on:[[:space:]]*\[\(.*\)\].*/\1/p' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -v '^$'
}

# Commits since <stamp> that changed code *directly* in <dir>. Nested subfolders
# are excluded: they belong to their own docs, the same boundary check C draws.
# Without this, a pathspec of `scenes` also matches scenes/map/ and scenes/hero/,
# and every change anywhere under scenes/ would flag every doc depending on it.
direct_code_commits() {
  d="$1"
  stamp="$2"
  git rev-list --no-merges "${stamp}..HEAD" -- "$d" | while IFS= read -r c; do
    hit=$(git show --pretty=format: --name-only "$c" -- "$d" \
      | while IFS= read -r f; do
          [ -n "$f" ] || continue
          [ "$(dirname "$f")" = "$d" ] || continue
          printf '%s\n' "$f"
        done | grep -E "$CODE_RE")
    [ -n "$hit" ] && git log -1 --format='%h %s' "$c"
  done
}

check_graph() {
  folder_docs | while IFS= read -r doc; do
    d=$(dirname "$doc")

    # Three ways this goes wrong, and every one of them has to be loud. A
    # missing block is obvious, and a block omitting the key nearly so. The
    # third is not: an unbracketed `depends-on: scenes` satisfies a bare key
    # test, while declared_deps extracts nothing from it -- so the doc reads as
    # having no dependencies, indistinguishable from a deliberate `[]`, and no
    # BADDEP or DEPSTALE can ever fire for it. That is this check's own failure
    # mode reproduced inside its parser, so the gate demands the bracket form.
    if ! sed -n '1p' "$doc" | grep -qx -- '---' \
       || ! sed -n '2,/^---$/p' "$doc" | grep -q '^depends-on:[[:space:]]*\[.*\]'; then
      echo "NOFRONT     $doc"
      echo "            no 'depends-on: [...]' key in a frontmatter block on line 1"
      continue
    fi

    stamp=$(sed -n 's/.*verified-against:[[:space:]]*\([0-9a-fA-F]\{7,40\}\).*/\1/p' "$doc" | tail -1)

    declared_deps "$doc" | while IFS= read -r dep; do
      if [ "$dep" = "$d" ]; then
        echo "SELFDEP     $doc"
        echo "            depends-on lists its own folder"
        continue
      fi
      if [ ! -f "$dep/CLAUDE.md" ]; then
        echo "BADDEP      $doc"
        echo "            depends-on: $dep — no such folder doc ($dep/CLAUDE.md)"
        continue
      fi

      # Staleness across the edge. Skipped when this doc has no usable stamp;
      # check C already reports that, and one fault should not produce two.
      [ -n "$stamp" ] || continue
      git rev-parse --verify --quiet "${stamp}^{commit}" >/dev/null 2>&1 || continue

      upstream=$(direct_code_commits "$dep" "$stamp")
      [ -n "$upstream" ] || continue
      echo "DEPSTALE    $doc"
      echo "            depends on $dep/, whose code changed since $stamp:"
      printf '%s\n' "$upstream" | sed 's/^/              /'
    done
  done
}

problems=$(
  check_same_change
  check_code_map
  check_verification
  check_graph
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
  echo "NOFRONT     add a frontmatter block on line 1 naming the folders this"
  echo "            doc's claims rest on:  ---\\ndepends-on: [scenes, assets]\\n---"
  echo "            Declaring none is 'depends-on: []' — an explicit claim, not"
  echo "            an omitted key, which nothing could tell from forgetting."
  echo "SELFDEP     drop the self-reference; a folder does not depend on itself."
  echo "BADDEP      the named folder has no CLAUDE.md — fix the name or add the doc."
  echo "DEPSTALE    a folder this doc depends on changed. Re-read this doc against"
  echo "            those commits: its claims rest on code that moved. Correct what"
  echo "            no longer holds, then bump this doc's stamp. This is the check"
  echo "            that catches drift arriving from outside the folder."
  echo "NOSTAMP     append to the doc:  <!-- verified-against: \$(git rev-parse --short HEAD) -->"
  echo "UNVERIFIED  read the listed commits against the doc, correct whatever no"
  echo "            longer holds, then bump the stamp to the current HEAD. Bump it"
  echo "            only once the doc is actually true — the stamp is a claim that"
  echo "            someone checked, and it is the only such claim in the repo."
} >&2
exit 2
