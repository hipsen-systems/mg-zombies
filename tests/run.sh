#!/usr/bin/env bash
# Runs every headless smoke test and fails if any of them does.
#
# One runner for CI and for a developer, deliberately: the `build-check`
# workflow calls this script rather than writing its own loop, so "it passes
# locally" and "it passes on the PR" are statements about the same thing.
#
#   bash tests/run.sh "$GODOT"        # path to the Godot binary, or $GODOT
#
# Each test is a SceneTree script that brings up the real scenes/main.tscn and
# exits non-zero if an assertion fails — see tests/CLAUDE.md.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2

GODOT="${1:-${GODOT:-}}"
if [ -z "$GODOT" ]; then
  echo "usage: tests/run.sh <path-to-godot>   (or set \$GODOT)" >&2
  echo "       the path is machine-specific and lives in CLAUDE.local.md" >&2
  exit 2
fi

# --fixed-fps unhooks the main loop from the wall clock, so a run costs what the
# machine can compute rather than the duration it simulates: the traversal test
# is 28 s of game time in ~1.5 s. It is also half of what makes a run
# repeatable — see RNG_SEED in tests/harness.gd for the other half. 60 to match
# the project's physics tick rate; they should move together.
FIXED_FPS=60

tests=$(ls tests/smoke_*.gd 2>/dev/null)
if [ -z "$tests" ]; then
  # Not "nothing to do". A glob that stops matching — a rename, a moved folder —
  # would otherwise turn the whole suite off and report success for it, which is
  # the one failure a test runner must never have.
  echo "FAIL  no tests/smoke_*.gd found — the suite would pass vacuously" >&2
  exit 1
fi

failed=''
for test in $tests; do
  echo "--- $test"
  # Every test is run even after one fails: a first red test very often makes
  # the rest red too, and the set of them is the diagnosis.
  if ! "$GODOT" --headless --path . --fixed-fps "$FIXED_FPS" --script "res://$test"; then
    failed="$failed $test"
  fi
done

echo ''
if [ -n "$failed" ]; then
  echo "FAILED:$failed" >&2
  exit 1
fi
echo "All smoke tests passed."
