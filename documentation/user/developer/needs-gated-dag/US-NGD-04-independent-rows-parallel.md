# US-NGD-04 — Independent rows run in parallel

**User-type:** developer **Status:** spec

```gherkin
Given rows A and B that share no `needs` edge with each other
When the workflow fans out and both enter :pending
Then both readiness wheres are satisfied at the same time
And A and B run concurrently without one waiting on the other
```

## Acceptance criteria

- Rows with no edge between them have independent readiness `where` expressions,
  so the scheduler matches and enqueues both in the same pass.
- No global ordering is imposed by the engine — only declared `needs` edges
  constrain order; anything not on a `needs` chain runs in parallel.
- Triggers are generated per row's step state, each with its own readiness
  clause.

## Notes

- **Reference / related code:** `lib/ash_jobs/transformers/integrate_oban.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 13 — Readiness where-filter](../../../../../../docs/tasks/workflow-dag-engine/13-readiness-where-filter.md) — the work that makes this story true.

## See also

- [US-NGD-03](US-NGD-03-start-after-all-needs-success.md) — the gating case that
  serializes rows along a `needs` chain.
- [US-NGD-08](../../operator/needs-gated-dag/US-NGD-08-concurrent-independent-rows.md)
  — the operator-observable view of these independent rows running concurrently.
