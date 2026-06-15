# US-DOC-02 — Every `US-*` story has a referencing test

**User-type:** qa-engineer **Status:** spec

```gherkin
Given the ash_jobs story files under `documentation/**/US-*.md`
When a `US-*` story has no test that references it via `@tag story:`
Then the untested-story ratchet counts it against the baseline, and adding a new untested story grows the count and fails the build
```

## Acceptance criteria

- The SuiteCheck enumerates every `US-…` id from the `:docs` glob, subtracts ids
  referenced by `@tag story:`, and compares the remainder against
  `test/traceability_untested_baseline.txt`.
- The untested count can only hold or shrink; a new story with no verifying test
  pushes the count above the baseline and fails.

## Notes

- **Reference / related code:**
  `packages/story_traceability/lib/story_traceability/suite_check.ex`, the
  ratchet baseline `test/traceability_untested_baseline.txt`,
  `packages/story_traceability/lib/story_traceability/ratchet.ex`.
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 23 — Doc-conformance gate](../../../../../../docs/tasks/workflow-dag-engine/23-doc-conformance-gate.md) — the work that makes this story true.

## See also

- [US-DOC-01](US-DOC-01-every-test-tagged.md) — the complementary ratchet on the
  test side: every test must carry a `@tag story:`.
- [US-DOC-03](US-DOC-03-unknown-story-tag-fails.md) — guards the tag-to-story
  mapping this ratchet relies on by failing on unknown story ids.
- [US-DOC-04](US-DOC-04-story-missing-gwt-fails.md) — guards story quality by
  rejecting stories that lack a Given/When/Then.
