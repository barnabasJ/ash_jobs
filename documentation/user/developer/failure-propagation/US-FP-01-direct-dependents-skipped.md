# US-FP-01 — When a row fails, its direct dependents are skipped, not started

**User-type:** developer **Status:** spec

```gherkin
Given a workflow row B whose `needs` lists row A, and A is still in progress
When A transitions into its `:failed` state
Then B is transitioned to `:skipped` rather than having its first workflow step triggered
```

## Acceptance criteria

- A row that directly `needs` a failed row transitions to `:skipped`.
- The skipped row's initial workflow step is never triggered (no
  `AshOban.run_trigger`).

## Notes

- **Reference / related code:** `packages/ash_jobs/lib/ash_jobs/change.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 16 — :skipped state + propagation](../../../../../../docs/tasks/workflow-dag-engine/16-skip-state-and-propagation.md) — the work that makes this story true.

## See also

- [US-FP-02](US-FP-02-transitive-skip-propagation.md) — extends this direct skip
  across the full `needs` graph.
- [US-FP-03](US-FP-03-skipped-terminal-state.md) — adds the `:skipped` terminal
  state this transition targets.
- [US-FP-05](../../operator/failure-propagation/US-FP-05-dependents-never-stuck-pending.md)
  — operator-facing guarantee that skipped dependents never stay pending.
