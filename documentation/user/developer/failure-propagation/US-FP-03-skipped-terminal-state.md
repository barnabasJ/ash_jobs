# US-FP-03 — A `:skipped` terminal state is added to the generated state machine

**User-type:** developer **Status:** spec

```gherkin
Given a workflow resource using the AshJobs extension
When the `IntegrateStateMachine` transformer generates the state machine
Then `:skipped` is present in the generated terminal states alongside `:completed`, `:failed`, and `:cancelled`
```

## Acceptance criteria

- `:skipped` is included in the generated `terminal_states`.
- The state attribute's `one_of` constraint accepts `:skipped` as a transition
  target.
- The initial state and success routing are unchanged.

## Notes

- **Reference / related code:**
  `packages/ash_jobs/lib/ash_jobs/transformers/integrate_state_machine.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 16 — :skipped state + propagation](../../../../../../docs/tasks/workflow-dag-engine/16-skip-state-and-propagation.md) — the work that makes this story true.

## See also

- [US-FP-01](US-FP-01-direct-dependents-skipped.md) — uses this `:skipped` state
  as the target for directly-blocked dependents.
- [US-FP-02](US-FP-02-transitive-skip-propagation.md) — uses this `:skipped`
  state as the target for transitively-blocked rows.
- [US-FP-04](US-FP-04-skipped-counted-by-completion.md) — relies on `:skipped`
  being terminal so completion counting resolves.
