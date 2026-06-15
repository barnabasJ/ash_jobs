# US-FP-05 — A failed upstream row surfaces dependents as skipped, never stuck pending

**User-type:** operator **Status:** spec

```gherkin
Given a running workflow whose upstream row fails partway through the DAG
When I inspect the downstream rows that depended on it via `needs`
Then every blocked dependent is in the `:skipped` terminal state and none remain indefinitely in a pending/in-progress state
```

## Acceptance criteria

- Every reverse-`needs` dependent of a failed row reaches the `:skipped`
  terminal state.
- No dependent remains in a pending/in-progress state after the run resolves.
- The parent's completion strategy resolves rather than hanging.

## Notes

- **Reference / related code:** `packages/ash_jobs/lib/ash_jobs/change.ex`,
  `packages/ash_state_machine/lib/parallel_coordinator.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 16 — :skipped state + propagation](../../../../../../docs/tasks/workflow-dag-engine/16-skip-state-and-propagation.md) — the work that makes this story true.

## See also

- [US-FP-01](../../developer/failure-propagation/US-FP-01-direct-dependents-skipped.md)
  — the developer mechanism that skips direct dependents of a failed row.
- [US-FP-02](../../developer/failure-propagation/US-FP-02-transitive-skip-propagation.md)
  — the developer mechanism that propagates skips across the whole `needs`
  closure.
