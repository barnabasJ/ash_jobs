# US-NGD-05 — A need reaching success pushes its dependents to ready (no poll wait)

**User-type:** developer **Status:** spec

```gherkin
Given row D that `needs` row A and is its only unmet dependency
When A's step action succeeds and A transitions to a success state
Then A's success after-action re-runs the trigger for D's step
And D becomes ready without waiting for the next scheduler poll
```

## Acceptance criteria

- On a successful step transition, the success after-action fans the run-trigger
  call to the edge dependents, so a freshly-satisfied row is evaluated and
  enqueued immediately instead of waiting a poll interval.
- The dependent still only runs if its full readiness `where` holds — a push
  that leaves other needs unmet is a no-op.

## Notes

- **Reference / related code:** `lib/ash_jobs/change.ex`
  (`AshJobs.Change.handle_workflow_step/3`, `AshOban.run_trigger/2`)
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 14 — Push on completion](../../../../../../docs/tasks/workflow-dag-engine/14-push-on-completion.md) — the work that makes this story true.

## See also

- [US-NGD-03](US-NGD-03-start-after-all-needs-success.md) — the readiness gate
  that still must hold for a pushed dependent to actually run.
- [US-NGD-06](US-NGD-06-poll-advances-without-push.md) — the poll backstop that
  advances ready rows when no success push fires.
