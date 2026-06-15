# US-NGD-09 — Ordering is expressed via `needs`, not `sort_order`

**User-type:** agent **Status:** spec

```gherkin
Given I am an agent authoring a workflow file with several steps
When I want step B to run after step A
Then I declare `needs: [A]` on B as a relationship between rows
And I do not assign or reason about any global sort_order / index field
```

## Acceptance criteria

- Ordering is declared by stating only what a row depends on (`needs: [A]`); the
  engine derives execution order, with no global numbering to keep consistent
  and no renumbering when a step is inserted.
- Each edge is a local, self-describing fact ("B needs A") that the readiness
  `where` turns into execution order, leaving everything unconnected free to run
  in parallel — cheaper in tokens and context than a `sort_order` scheme.

## Notes

- **Reference / related code:** `lib/ash_jobs/transformers/integrate_oban.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 12 — needs edge DSL](../../../../../../docs/tasks/workflow-dag-engine/12-needs-edge-dsl.md) — the work that makes this story true.
- [Task 13 — Readiness where-filter](../../../../../../docs/tasks/workflow-dag-engine/13-readiness-where-filter.md) — the work that makes this story true.

## See also

- [US-NGD-01](../../developer/needs-gated-dag/US-NGD-01-declare-needs-edge.md) —
  how the `needs` edge an agent declares is persisted and gated.
