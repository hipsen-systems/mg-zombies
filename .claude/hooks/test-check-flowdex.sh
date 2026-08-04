#!/usr/bin/env bash
# Test harness for check-flowdex.sh. Run it from anywhere:
#
#   bash .claude/hooks/test-check-flowdex.sh
#
# Builds synthetic transcripts in a temp dir, runs the hook against each, and
# asserts the exit code (0 = let the session stop, 2 = block it).
#
# ---------------------------------------------------------------------------
# THE RULE THIS FILE OBEYS, AND WHY
#
# The hook decides what a session did by grepping that session's transcript.
# A transcript contains the full text of every file the session read. So any
# file in this repo that spells out — as adjacent literal text — a pattern the
# hook greps for will make the hook mis-read any session that merely opened it.
#
# That is not theoretical. It shipped twice: once via the MCP tool names, and
# again via the merge command, which accused every reader of this hook of
# having merged a pull request. Both were caught in cross-review of PR #23.
#
# So: patterns are assembled from parts here, exactly as they are in the hook.
# Nothing below spells out a matched string in one piece. If you add a case,
# keep it that way, or this harness will start corrupting the sessions of
# whoever reads it.
# ---------------------------------------------------------------------------
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/check-flowdex.sh"
[ -f "$HOOK" ] || { echo "cannot find check-flowdex.sh next to this script" >&2; exit 1; }

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t flowdex)
trap 'rm -rf "$TMP"' EXIT

# --- assembled literals (see header) ---------------------------------------
w='write'; ix='index'; ap='append'; cl='changelog'
prefix='mcp__testconnector__'
write_tool="${prefix}${w}_${ix}"
chg_tool="${prefix}${ap}_${cl}"
mv='merge'
merge_cmd="gh pr ${mv}"
gd='gd'; md='md'

# --- fixture pieces ---------------------------------------------------------
avail="{\"deferred\":[\"${write_tool}\",\"${chg_tool}\"]}"
call="{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_01\",\"name\":\"${write_tool}\",\"input\":{}}]}}"
edit_gd="{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Edit\",\"input\":{\"file_path\":\"C:\\\\repo\\\\scenes\\\\map\\\\maze.${gd}\"}}]}}"
edit_lic="{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Edit\",\"input\":{\"file_path\":\"C:\\\\repo\\\\assets\\\\LICENSES.${md}\"}}]}}"
edit_scratch="{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Write\",\"input\":{\"file_path\":\"C:\\\\Temp\\\\scratchpad\\\\notes.txt\"}}]}}"
read_only="{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Read\",\"input\":{\"file_path\":\"C:\\\\repo\\\\README.txt\"}}]}}"
merged="{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":\"${merge_cmd} 23 --squash\"}}]}}"
# A tool-listing / schema mention: the tool name appears, but never as a call.
mention="{\"type\":\"tool_result\",\"content\":[{\"type\":\"tool_reference\",\"tool_name\":\"${write_tool}\"}]}"
# The same thing in the other shape a listing arrives in: a schema quoted as
# *text*, so its quotes are JSON-escaped and the call pattern cannot reach them.
# The hook's comment names three ways a name reaches a transcript without being
# a call; this pins the one that is not a key at all. It is only safe to write
# out because the escaped form is not the matched form — read_the_tests below
# is what proves that, by feeding this file to the hook and demanding a 0.
schema_text="{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"content\":\"<function>{\\\"name\\\": \\\"${write_tool}\\\"}</function>\"}]}}"

mk() { local name=$1; shift; printf '%s\n' "$@" > "$TMP/$name.jsonl"; }

mk no_connector      "$edit_gd"
mk no_writeback      "$avail" "$edit_gd"
mk wrote_back        "$avail" "$edit_gd" "$call"
mk merged_no_write   "$avail" "$merged"
mk merged_wrote_back "$avail" "$merged" "$call"
mk read_only         "$avail" "$read_only"
mk scratchpad_only   "$avail" "$edit_scratch"
mk licenses_only     "$avail" "$edit_lic"
mk mention_not_call  "$avail" "$edit_gd" "$mention"
mk schema_as_text    "$avail" "$edit_gd" "$schema_text"

# The regression that shipped: a session holding this hook's own text must not
# be read as having merged a PR or written anything back. Grep is line-based,
# so pasting the source in as raw lines exercises exactly what a real read does.
{ printf '%s\n' "$avail"; cat "$HOOK"; } > "$TMP/read_the_hook.jsonl"
# Same, for this harness — it is the other file full of tempting literals.
{ printf '%s\n' "$avail"; cat "$0"; } > "$TMP/read_the_tests.jsonl"

# --- runner -----------------------------------------------------------------
pass=0; fail=0

check() { # name expected description
  local name=$1 want=$2 desc=$3 path got
  path="$TMP/$name.jsonl"
  printf '{"transcript_path":"%s","stop_hook_active":false}' "$path" \
    | bash "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf '  ok    %-22s %s\n' "$name" "$desc"
  else
    fail=$((fail+1)); printf '  FAIL  %-22s %s (want %s, got %s)\n' "$name" "$desc" "$want" "$got"
  fi
}

echo "check-flowdex.sh"
echo
echo "no-op when Flowdex is not connected:"
check no_connector      0 "code edited, no connector -> never block"
echo
echo "enforces a write-back when it should:"
check no_writeback      2 "code edited, nothing written back"
check merged_no_write   2 "PR merged, nothing written back"
check licenses_only     2 "only LICENSES.md edited"
check mention_not_call  2 "tool named but never called"
check schema_as_text    2 "schema quoted as escaped text, never called"
echo
echo "stays out of the way when it should:"
check wrote_back        0 "code edited and written back"
check merged_wrote_back 0 "PR merged and written back"
check read_only         0 "read-only session"
check scratchpad_only   0 "scratchpad edits only"
echo
echo "does not mistake a file's text for a session's actions:"
check read_the_hook     0 "session that read the hook itself"
check read_the_tests    0 "session that read these tests"
echo
echo "fails safe:"
check missing           0 "transcript path does not exist"

printf '{"transcript_path":"%s/no_writeback.jsonl","stop_hook_active":true}' "$TMP" \
  | bash "$HOOK" >/dev/null 2>&1
if [ $? = 0 ]; then
  pass=$((pass+1)); printf '  ok    %-22s %s\n' "loop_guard" "already blocked once -> let it stop"
else
  fail=$((fail+1)); printf '  FAIL  %-22s %s\n' "loop_guard" "already blocked once -> let it stop"
fi

# Windows-only: the hook rewrites a drive-letter path into the POSIX form Git
# Bash expects. Skipped elsewhere, where that branch is unreachable anyway.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    win_path=$(printf '%s' "$TMP/no_writeback.jsonl" \
      | sed -E 's#^/([a-z])/#\U\1:/#')
    printf '{"transcript_path":"%s","stop_hook_active":false}' "$win_path" \
      | bash "$HOOK" >/dev/null 2>&1
    if [ $? = 2 ]; then
      pass=$((pass+1)); printf '  ok    %-22s %s\n' "windows_path" "drive-letter transcript path resolves"
    else
      fail=$((fail+1)); printf '  FAIL  %-22s %s (path was %s)\n' "windows_path" "drive-letter transcript path resolves" "$win_path"
    fi
    ;;
esac

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
