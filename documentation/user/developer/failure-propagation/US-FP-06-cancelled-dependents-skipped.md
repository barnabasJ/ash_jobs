# US-FP-06 — When a row is cancelled, its dependents are skipped, not started

**User-type:** developer **Status:** spec

```gherkin
Given a workflow row B whose `needs` lists row A, and A is still pending
When A is cancelled (transitions into its `:cancelled` terminal state)
Then B is transitioned to `:skipped` rather than having its first workflow step triggered, because `:cancelled` is a non-success terminal just like `:failed`
```

## Acceptance criteria

- `:cancelled` is a non-success (failure) terminal state, so a row that directly
  `needs` a cancelled row transitions to `:skipped` rather than starting.
- The needs gate never treats a cancelled need as satisfied — the dependent's
  initial workflow step is never triggered (`run_count` stays `0`).
- Skip propagation is transitive: dependents-of-dependents of a cancelled row
  are skipped too.

## Notes

- **Reference / related code:**
  `packages/ash_jobs/lib/ash_jobs/transformers/integrate_state_machine.ex`
  (`failure_terminal_states/0` classifies `:cancelled` as non-success),
  `packages/ash_jobs/lib/ash_jobs/change.ex` (the
  `terminal_state? -> propagate_skip` routing),
  `packages/ash_jobs/lib/ash_jobs/failure_propagation.ex`.

## See also

- [US-FP-01](US-FP-01-direct-dependents-skipped.md) — the same skip behavior
  triggered by `:failed` rather than `:cancelled`.
- [US-FP-02](US-FP-02-transitive-skip-propagation.md) — transitive skip
  propagation through the needs graph.
