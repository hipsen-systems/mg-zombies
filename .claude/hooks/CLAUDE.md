# .claude/hooks

Stop hooks that enforce two of this project's documentation rules. Both are
wired up in `../settings.json` and run on every session stop, independently —
one failing does not prevent the other from running.

- `check-folder-docs.sh` — enforces the per-folder `CLAUDE.md` rule. Also runs
  in CI via `--diff <range>`.
- `check-flowdex.sh` — enforces the Flowdex write-back rule (see "Knowledge
  base" in the root `CLAUDE.md`). No-ops for a developer who has not connected
  the Flowdex MCP server.
- `test-check-flowdex.sh` — test harness for the above. Run it after any change
  to `check-flowdex.sh`:

  ```bash
  bash .claude/hooks/test-check-flowdex.sh
  ```

## The gotcha: these scripts read transcripts, so they can read themselves

`check-flowdex.sh` decides what a session did by grepping that session's
transcript — and a transcript contains the full text of every file the session
read. **Any file in this repo that spells out, as adjacent literal text, a
pattern the hook greps for will make the hook mis-read any session that merely
opened that file.**

This shipped twice before it was understood, both caught in cross-review of
PR #23: once through the MCP tool names, and again through the merge command,
which accused every reader of the hook of having merged a pull request.

So patterns are assembled from parts at runtime rather than written out whole,
in the hook *and* in its tests. Keep it that way when editing either, and keep
the joined forms out of the root `CLAUDE.md` too — that file is injected into
every session's context, so it reaches transcripts the same way.

`test-check-flowdex.sh` covers this directly: it feeds the hook a transcript
containing the hook's own source, and another containing the tests' source,
and requires both to be treated as sessions that did nothing.
