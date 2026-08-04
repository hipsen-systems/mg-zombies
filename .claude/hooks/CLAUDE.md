---
depends-on: []
---

# .claude/hooks

Stop hooks that enforce two of this project's documentation rules. Both are
wired up in `../settings.json` and run on every session stop, independently —
one failing does not prevent the other from running.

- `check-folder-docs.sh` — enforces the documentation rules from the root
  `CLAUDE.md`, in four layers: **same-change** (code changed in a folder =>
  that folder's doc changed too), **code map** (every code folder is linked from
  the root's map, and every entry resolves), **verification** (every folder
  doc carries a `verified-against: <sha>` stamp, and its folder has not changed
  since without the doc being touched), and **dependency graph** (every folder
  doc *declares* `depends-on: [...]` — `[]` if it has none — each entry
  resolves, and no doc is left unread after code it depends on moved). Runs
  here as a Stop hook, in CI on every
  PR via `--diff <range>`, and on push to `main` via `--audit` — the PR gate
  only sees one range, so it cannot see drift arriving another way.

  The first three all examine a folder in isolation, which is why the fourth
  exists: it is the only one that can see a doc invalidated from outside its own
  folder. It found real debt on its first run — `scenes/CLAUDE.md` was stale
  against two `scenes/map/maze.gd` commits.

  **The frontmatter parser is the third thing here to hit the self-reference
  trap, and it hit it twice.** `depends-on:` is read from line 2 to the first
  closing `---`, never with a `/^---$/,/^---$/` range: sed restarts a range at
  every later match, so a markdown horizontal rule further down a doc reopens
  it, and any prose line starting `depends-on:` is then read as a real edge. A
  doc explaining this convention would be misparsed by the parser it explains —
  the same shape as the stamp parser taking the *last* match, and as the Flowdex
  hook reading its own source. Assume any parser added here will hit it too.

  The second half of that was issue #34: `2,/^---$/` has no terminator if the
  closing `---` is missing, so it reads to end of file and the same prose line
  is parsed as an edge by a different route. **The close is now required rather
  than assumed** — `frontmatter_closed` answers whether there is a block at all
  and `frontmatter` prints nothing when there is not, so callers have to report
  the absence instead of receiving an empty parse. Anything reading frontmatter
  should go through those two, not re-derive a range.

  **The bracket form is required, and the reason is not cosmetic.** An
  unbracketed `depends-on: scenes` — or a list wrapped over several lines —
  satisfies a bare key test while the parser extracts nothing from it, so the
  doc reads as having no dependencies, indistinguishable from a deliberate `[]`,
  with no `BADDEP` or `DEPSTALE` able to fire for it ever again. That is this
  check's own failure mode reproduced inside its parser, which is why the gate
  tests for `[...]` rather than for the key alone. The general lesson: every
  gate here should ask whether a *malformed* input is silently read as an
  *empty* one.

  **`NOFRONT` says which of the three it is**, and that is worth keeping. The
  single message it used to print — "no `depends-on: [...]` key in a
  frontmatter block on line 1" — sent anyone with a wrapped list looking for a
  key that was plainly there (issue #34). No block, a block without the key, and
  a key in an unparseable form now read differently.

  **Both graph and stamp checks must exclude nested subfolders.** A git pathspec
  of `scenes` also matches `scenes/map/` and `scenes/hero/`, so the first version
  of the graph check reported `scenes/map/CLAUDE.md` as stale against commits
  that had only touched `scenes/map/` itself. `direct_code_commits` filters to
  direct children, matching the boundary the verification check already drew —
  keep them in step if either is edited.

  `--audit` runs the history checks alone against any checkout, and is the
  one-command answer to "are these docs still trustworthy?".

  **A stamp can name a real commit and still be impossible, and the
  verification check cannot see it** (issue #35). It asks whether the folder
  changed since the stamp without the doc changing; a stamp from *before the
  folder existed* passes that trivially, because there are no such commits.
  Two guards run first and fail closed: `PREDATES` (the folder does not exist
  at that commit) and `UNREACHABLE` (the commit is not an ancestor of `HEAD`,
  so it is a sha copied from elsewhere in the history rather than one this
  branch was read at). The second is deliberately stricter locally than in CI,
  where the PR job checks out the merge with `main` and so has more ancestors —
  starting every branch fresh from `origin/main` is what keeps the two agreeing.
  Both repair by repointing the stamp, never by re-auditing: like a rewritten
  history, nothing about the doc became untrue.

  It found live debt on its first run, exactly as the graph check did:
  `tests/CLAUDE.md` was stamped at `200ccec`, one merge before `tests/` was
  created.

  Note the ceiling: all four verify a doc was *edited*, never that it is
  *true*. The stamp does not change that — it makes the human judgement
  explicit and attributable, so a stale stamp becomes a reviewable finding.
  Bump one only after actually reading the doc against the code.

  **Minting a folder's first stamp across a merge.** Ordinary work never needs
  to move a stamp, because a commit that changes a folder and its doc together
  satisfies the check whatever the stamp says. The exception is a *first* stamp
  for a folder whose history carries unaccompanied commits on both sides of a
  merge — as `.claude/hooks/` did, with `4aab9d6` on `main` and `e667baf` on
  the branch that added these checks. No commit has both as ancestors until the
  merge itself, so no pre-merge sha yields a clean stamp. Land the merge, then
  stamp at the merge commit in a follow-up. That is the whole workaround.
- `check-flowdex.sh` — enforces the Flowdex write-back rule (see "Knowledge
  base" in the root `CLAUDE.md`). No-ops for a developer who has not connected
  the Flowdex MCP server.

  **What separates a call from a mention is a shape, not a key name** (issue
  #27). The write-back probe requires the tool name under a key spelled exactly
  `name`, which is how a call is recorded; the three other ways a name reaches a
  transcript each miss for their own reason — a different key on a tool-search
  reference entry, no key at all in a bare listing, and backslash-escaped quotes
  in a schema quoted as text. So the thing that would kill enforcement silently
  is a transcript format storing a tool *listing* in the structured shape a call
  uses, by any route. The comment above that grep used to name only the key
  rename, which is one of the three and would send a maintainer to re-test the
  wrong thing. Re-test by opening a real transcript from a session that *loaded*
  these tools without calling them and confirming the pattern finds nothing.
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

<!-- verified-against: a0a19fc -->
