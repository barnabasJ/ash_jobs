# US-NGD-07 — A fanned-out row with unmet needs does not self-start on create

**User-type:** developer **Status:** spec

```gherkin
Given a fanned-out row that `needs` a sibling not yet in a success state
When the row is created and its create action's after-action fires
Then the initial-step trigger does not start the row's work
And the row stays :pending until its readiness where is satisfied
```

## Acceptance criteria

- The create-trigger guard defers to the readiness `where`: a row created with
  unmet `needs` is enqueued but immediately filtered out by its trigger's
  `where` rather than running ahead of its dependencies.
- The row waits in `:pending` until a push or poll finds its needs satisfied —
  fan-out create never short-circuits the gate.

## Notes

- **Reference / related code:** `lib/ash_jobs/change.ex`
  (`AshJobs.Change.handle_create_action/2`)
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 13 — Readiness where-filter](../../../../../../docs/tasks/workflow-dag-engine/13-readiness-where-filter.md) — the work that makes this story true.
- [Task 15 — Create-trigger guard](../../../../../../docs/tasks/workflow-dag-engine/15-create-trigger-guard.md) — the work that makes this story true.

## See also

- [US-NGD-03](US-NGD-03-start-after-all-needs-success.md) — the readiness gate
  the create-trigger guard defers to instead of self-starting.
