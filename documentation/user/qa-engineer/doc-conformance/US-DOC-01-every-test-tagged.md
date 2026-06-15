# US-DOC-01 — Every test in the package carries a `@tag story:`

**User-type:** qa-engineer **Status:** spec

```gherkin
Given the ash_jobs test suite with the StoryTraceability.SuiteCheck gate wired in
When a test in `packages/ash_jobs/test/**/*_test.exs` carries no `@tag story:`
Then the untagged-test ratchet counts it against the baseline, and adding a new untagged test grows the count and fails the build
```

## Acceptance criteria

- The SuiteCheck counts every `test` lacking a `@tag story:` and compares it
  against `test/traceability_untagged_baseline.txt`.
- Pre-existing untagged tests stay green at the baseline; a newly added untagged
  test raises the count above the baseline and fails.

## Notes

- **Reference / related code:**
  `packages/story_traceability/lib/story_traceability/suite_check.ex`, the
  ratchet baseline `test/traceability_untagged_baseline.txt`,
  `packages/story_traceability/lib/story_traceability/coverage.ex`.
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 23 — Doc-conformance gate](../../../../../../docs/tasks/workflow-dag-engine/23-doc-conformance-gate.md) — the work that makes this story true.

## See also

- [US-DOC-02](US-DOC-02-every-story-tested.md) — the complementary ratchet on
  the story side: every `US-*` story must have a referencing test.
