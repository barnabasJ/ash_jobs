# US-SPS-03 — Static parallel steps retain their `on_error` routing

**User-type:** developer **Status:** spec

```gherkin
Given a workflow author declares a fixed-resource `parallel_step` with `on_error :handle_error`
When the workflow DSL compiles
Then the `ParallelStep` stores the `on_error` target
And the generated state-machine integration does not crash while processing the parallel step entity
```

## Acceptance criteria

- A static `parallel_step` with `on_error` compiles successfully.
- Spark introspection exposes the configured `on_error` target on the
  `ParallelStep` entity.
- The state-machine transformer treats `ParallelStep` as a state-owning workflow
  entity even though it has no `:from` field.

## Notes

- **Reference / related code:**
  `lib/ash_jobs/dsl/entities/parallel_step.ex`,
  `lib/ash_jobs/transformers/integrate_state_machine.ex`
- **Size:** <= ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 01 — Green the ash_jobs test suite](../../../../../../docs/tasks/workflow-dag-engine/01-ash-jobs-test-cleanup.md) — fixes the `ParallelStep` transformer crash and preserves `on_error` compilation.

## See also

- [US-WEH-01](../workflow-error-handling/US-WEH-01-error-handler-payloads.md) —
  generated error handler actions used by normal workflow error routing.
