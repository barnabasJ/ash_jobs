# US-DOC-04 — A story file with no Given/When/Then fails the gate

**User-type:** qa-engineer **Status:** spec

```gherkin
Given a `US-*.md` story file under `documentation/**/`
When the file does not spell out a Given/When/Then scenario
Then the StoryTraceability.SuiteCheck gate fails, because each per-story file must declare a Given/When/Then
```

## Acceptance criteria

- The SuiteCheck parses each `US-*` file from the `:docs` glob and rejects any
  that omits a `Given`/`When`/`Then`.
- A story declared as a hollow stub (no GWT) fails the gate, so acceptance
  criteria must be written down before the story counts.

## Notes

- **Reference / related code:**
  `packages/story_traceability/lib/story_traceability/suite_check.ex`,
  `packages/story_traceability/lib/story_traceability/coverage.ex`.
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 23 — Doc-conformance gate](../../../../../../docs/tasks/workflow-dag-engine/23-doc-conformance-gate.md) — the work that makes this story true.

## See also

- [US-DOC-02](US-DOC-02-every-story-tested.md) — counts each `US-*` story; this
  story ensures those stories are real (Given/When/Then), not hollow stubs.
