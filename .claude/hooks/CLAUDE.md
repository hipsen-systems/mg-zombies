# .claude/hooks

Stop hooks that enforce two of this project's documentation rules. Both are
wired up in `../settings.json` and run on every session stop, independently —
one failing does not prevent the other from running.

- `check-folder-docs.sh` — enforces the documentation rules from the root
  `CLAUDE.md`, in three layers: **same-change** (code changed in a folder =>
  that folder's doc changed too), **code map** (every code folder is linked from
  the root's map, and every entry resolves), and **verification** (every folder
  doc carries a `verified-against: <sha>` stamp, and its folder has not changed
  since without the doc being touched). Runs here as a Stop hook, in CI on every
  PR via `--diff <range>`, and on push to `main` via `--audit` — the PR gate
  only sees one range, so it cannot see drift arriving another way.

  `--audit` runs the history checks alone against any checkout, and is the
  one-command answer to "are these docs still trustworthy?".

  Note the ceiling: all three verify a doc was *edited*, never that it is
  *true*. The stamp does not change that — it makes the human judgement
  explicit and attributable, so a stale stamp becomes a reviewable finding.
  Bump one only after actually reading the doc against the code.
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

<!-- verified-against: 4a45066 -->
