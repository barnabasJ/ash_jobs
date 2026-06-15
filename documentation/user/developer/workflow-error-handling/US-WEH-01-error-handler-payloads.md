# US-WEH-01 — Error-handler actions preserve payloads from valid states

**User-type:** developer **Status:** spec

```gherkin
Given a workflow author declares `on_error` handlers for active workflow steps
When a handler action is called from the state that owns that handler
Then the handler accepts string, map, or nil error payloads
And the workflow transitions to its configured terminal state with the extracted error message persisted
```

## Acceptance criteria

- Generated or user-defined error-handler actions accept an `:error` argument.
- A binary payload is persisted as the error message.
- A map payload with `:message` is persisted as the error message.
- A nil or unknown payload falls back to the handler's default message.
- The handler is exercised from a valid source state instead of reopening a
  terminal record.

## Notes

- **Reference / related code:**
  `lib/ash_jobs/transformers/generate_error_actions.ex`,
  `lib/ash_jobs/transformers/integrate_state_machine.ex`,
  `test/support/test_resources/branching_workflow.ex`
- **Size:** <= ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 01 — Green the ash_jobs test suite](../../../../../../docs/tasks/workflow-dag-engine/01-ash-jobs-test-cleanup.md) — corrects the error-handler edge-case test so each payload is exercised from a valid source state.

## See also

- [US-WEH-02](../../operator/workflow-error-handling/US-WEH-02-failure-visible-terminal-state.md) — the operator-visible result of those handler transitions.
