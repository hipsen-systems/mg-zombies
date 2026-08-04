#!/usr/bin/env bash
# Enforces the Flowdex write-back rule from the root CLAUDE.md: a session that
# changed project code, or merged a PR, must also have recorded something in the
# team wiki. Invoking the skill is not enough — the failure mode this exists for
# is loading context, then ending the session without writing any of it back,
# leaving the wiki describing a state of the project that no longer exists.
#
# No-ops for a developer who has not connected the Flowdex MCP server, so the
# hook is safe to ship to everyone (see "Knowledge base" in the root CLAUDE.md
# for how to connect it).
set -u

input=$(cat 2>/dev/null || true)

# Already blocked once this turn — let the stop through so we can't loop.
case "$input" in
  *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
esac

# Locate the transcript. If we can't read it we cannot judge, so never block.
# Any run of backslashes becomes one forward slash, so this copes with the
# JSON-escaped Windows path ("C:\\Users\\...") and a raw one alike.
transcript=$(printf '%s' "$input" \
  | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | sed 's/.*:[[:space:]]*"//; s/"$//' \
  | sed -E 's/\\+/\//g')
# Git Bash resolves "C:/..." fine, but a leading drive letter from a stripped
# path ("/c/...") is the form the POSIX layer expects.
case "$transcript" in
  [A-Za-z]:/*) transcript="/$(printf '%s' "${transcript%%:*}" | tr 'A-Z' 'a-z')${transcript#*:}" ;;
esac
[ -n "${transcript:-}" ] || exit 0
[ -f "$transcript" ] || exit 0

# The MCP tool names are assembled at runtime, never written out in full. The
# probe below searches the transcript for those names, and the transcript
# contains this file's own text whenever a session reads it — a literal here
# would make the hook believe Flowdex was connected in any session that opened
# it. Splitting the string keeps the file inert as evidence about itself.
mcp_prefix='mcp__[A-Za-z0-9_-]+__'
writeback_tools='(write_index|append_changelog)'

# Is Flowdex connected at all? The tool names appear in the session's tool
# listing whenever the MCP server is available, called or not. If they are
# absent entirely, this developer has no Flowdex connector and there is nothing
# to enforce — say nothing and get out of the way.
if ! grep -qE "${mcp_prefix}${writeback_tools}" "$transcript" 2>/dev/null; then
  exit 0
fi

# Two things oblige a write-back.
#
# (1) The session touched project code or docs. Scratchpad edits, questions and
#     read-only sessions should never be nagged.
#     LICENSES.md counts alongside CLAUDE.md: an asset addition may touch
#     nothing else, and the asset policy is exactly the kind of decision the
#     wiki is supposed to remember.
touched_code=0
if grep -E '"name": *"(Edit|Write|NotebookEdit)"' "$transcript" 2>/dev/null \
   | grep -qE '\.(gd|gdshader|tscn|godot|cfg|yml)"|(CLAUDE|LICENSES)\.md"'; then
  touched_code=1
fi

# (2) The session merged a PR. Accepting someone's work changes what is true on
#     `main` without this session editing a single file, which is exactly how
#     the wiki drifted behind the repo before. Matches the gh CLI and the raw
#     API call alike.
#
#     Assembled at runtime for the same reason as the tool names above, and it
#     is not a hypothetical here: written out whole, the command string sits in
#     this file, so any session that *read* this file — a review, a debug, an
#     edit to this very hook — put it in its own transcript and got accused of
#     merging a PR it never touched. Caught in cross-review of PR #23, after
#     the identical defence had already been applied to the tool names.
merge_verb='merge'
merged_pr=0
if grep -qE "gh pr ${merge_verb}|/pulls/[0-9]+/${merge_verb}" "$transcript" 2>/dev/null; then
  merged_pr=1
fi

if [ "$touched_code" -eq 0 ] && [ "$merged_pr" -eq 0 ]; then
  exit 0
fi

# Did it write anything back? This must match an actual tool *call*, not a
# mention. The tool names also appear in the session's tool listing, so a looser
# pattern is satisfied by merely having Flowdex connected — which is what the
# availability probe above deliberately uses it for.
#
# What separates the two is the *shape* a name is stored in, not the spelling of
# any one key — and the shape is the thing to re-test (issue #27). A call is
# recorded as an object carrying the name under a key spelled exactly `name`, so
# demanding a quote immediately before it is what makes the other three ways a
# name reaches a transcript miss. Each misses for its own reason, which is why
# no single one of them is the invariant:
#
#   a ToolSearch reference entry   files it under "tool_name":"<tool>"
#   a tool listing or a query      bare comma-separated names, no key at all
#   a schema quoted as text        JSON-escaped, so its quotes are backslashed
#                                  and the bare `"` here cannot match them
#
# Enforcement therefore dies silently the day a transcript format stores a tool
# *listing* in the same structured shape a real call uses — whether by renaming
# that key, by inlining schemas as JSON objects instead of as escaped text, or
# by some third route to the same place. Re-testing only "has the key been
# renamed?" would miss two of the three, which is what this comment used to send
# a maintainer off to do. The check that covers all of them: open a current
# transcript from a session that *loaded* these tools without calling them, and
# confirm this pattern still finds nothing in it.
#
# Measured 2026-08-04 across 30 real transcripts: 214 occurrences of the matched
# form, all 214 inside a tool_use entry, against 38 filed under `tool_name` and
# 3 sitting in escaped text. No false positive in any of them.
if grep -qE "\"name\"[[:space:]]*:[[:space:]]*\"${mcp_prefix}${writeback_tools}\"" "$transcript" 2>/dev/null; then
  exit 0
fi

{
  echo "Flowdex write-back missing (see 'Knowledge base' in the root CLAUDE.md)."
  echo ""
  if [ "$merged_pr" -eq 1 ]; then
    echo "This session merged a pull request but never called write_index or"
    echo "append_changelog. A merge changes what is true on 'main', and the wiki"
    echo "tracks 'main' — leaving it unwritten is how it drifts."
  else
    echo "This session changed project code or folder docs but never called"
    echo "write_index or append_changelog, so nothing durable was recorded."
  fi
  echo "Loading the skill at the start does not count — reading is half of it."
  echo ""
  echo "Before stopping:"
  echo "  1. Save what outlives this chat — an architecture or design decision,"
  echo "     a non-obvious gotcha, a convention — as a small single-topic page"
  echo "     under the right category folder, linked with [[wiki-links]]."
  echo "  2. Record the change itself with append_changelog."
  echo "  3. Fix any page this session made stale rather than appending a"
  echo "     correction to it."
  if [ "$merged_pr" -eq 1 ]; then
    echo "  4. Fold the merged PR's 'In flight — PR #N' block into the page body"
    echo "     and drop the heading; it is no longer in flight."
  fi
  echo ""
  echo "If this session genuinely produced nothing durable (a trivial rename, a"
  echo "revert), say so explicitly in one sentence and stop again."
} >&2
exit 2
