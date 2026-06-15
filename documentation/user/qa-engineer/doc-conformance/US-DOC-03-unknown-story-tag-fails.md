# US-DOC-03 — A `@tag story:` for a non-existent story fails immediately

**User-type:** qa-engineer **Status:** spec

```gherkin
Given the ash_jobs suite with the StoryTraceability.SuiteCheck gate wired in
When a test carries `@tag story:` naming an id that has no matching `US-*.md` file
Then the undocumented-tag check fails immediately rather than ratcheting, because the tag is a typo, not a coverage gap
```

## Acceptance criteria

- The SuiteCheck collects every story id referenced by `@tag story:` and asserts
  each exists as a `US-*` file in the `:docs` glob.
- This check is not baselined: a tag pointing at a missing or misspelled story
  id fails the build on its first appearance.

## Notes

- **Reference / related code:**
  `packages/story_traceability/lib/story_traceability/suite_check.ex`,
  `packages/story_traceability/lib/story_traceability/coverage.ex`.
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 23 — Doc-conformance gate](../../../../../../docs/tasks/workflow-dag-engine/23-doc-conformance-gate.md) — the work that makes this story true.

## See also

- [US-DOC-02](US-DOC-02-every-story-tested.md) — relies on a clean tag-to-story
  mapping; this story fails fast on tags naming a non-existent story.
