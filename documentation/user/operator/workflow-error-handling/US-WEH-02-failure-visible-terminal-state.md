# US-WEH-02 — Step failures are visible as failed terminal records

**User-type:** operator **Status:** spec

```gherkin
Given a running workflow has a configured `on_error` handler for the active step
When the active step fails during Oban-triggered execution
Then the workflow can be routed through the handler to `:failed`
And the persisted record exposes an error message explaining the failed step
```

## Acceptance criteria

- A failure at the first workflow step can be routed to the configured handler and
  persisted as `state == :failed`.
- A failure at a later workflow step can be routed to that step's configured
  handler and persisted as `state == :failed`.
- The persisted `error_message` is non-empty after the handler runs.
- Tests that intentionally exercise logged failures capture and assert the stable
  failure text instead of leaking uncaptured logs.

## Notes

- **Reference / related code:**
  `lib/ash_jobs/transformers/integrate_oban.ex`,
  `lib/ash_jobs/transformers/integrate_state_machine.ex`,
  `test/support/test_resources/branching_workflow.ex`
- **Size:** <= ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 01 — Green the ash_jobs test suite](../../../../../../docs/tasks/workflow-dag-engine/01-ash-jobs-test-cleanup.md) — captures intentional failure logs while preserving failed-state assertions.

## See also

- [US-WEH-01](../../developer/workflow-error-handling/US-WEH-01-error-handler-payloads.md) — the developer-authored handler action that produces the terminal state.
