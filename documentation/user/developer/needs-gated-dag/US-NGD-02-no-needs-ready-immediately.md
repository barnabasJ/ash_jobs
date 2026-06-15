# US-NGD-02 — A row with no `needs` becomes ready immediately

**User-type:** developer **Status:** spec

```gherkin
Given a fanned-out row that declares no `needs` edges
When the workflow fans out and the row enters :pending
Then the row's readiness where has no edge clause to satisfy
And the row is immediately ready to run its step action
```

## Acceptance criteria

- A row with zero `needs` has its edge clause collapse to vacuously true,
  leaving only the ordinary per-step state filter built by
  `build_state_where_expr/2`.
- The row matches its trigger as soon as it is in the step state, with no extra
  wait — identical to an edgeless workflow today.

## Notes

- **Reference / related code:** `lib/ash_jobs/transformers/integrate_oban.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 13 — Readiness where-filter](../../../../../../docs/tasks/workflow-dag-engine/13-readiness-where-filter.md) — the work that makes this story true.

## See also

- [US-NGD-01](US-NGD-01-declare-needs-edge.md) — declaring the `needs` edge this
  story shows the absence of.
- [US-NGD-03](US-NGD-03-start-after-all-needs-success.md) — the contrasting case
  where declared needs gate the row until they reach success.
