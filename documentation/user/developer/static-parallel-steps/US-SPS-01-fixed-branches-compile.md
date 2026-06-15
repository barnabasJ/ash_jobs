# US-SPS-01 — Fixed-resource branches compile and remain introspectable

**User-type:** developer **Status:** spec

```gherkin
Given a workflow author declares `parallel_step :process` with fixed-resource `branch :name, Resource` entries
When the resource compiles with AshJobs, AshStateMachine, and AshOban extensions
Then the resource loads successfully
And Spark introspection returns the `ParallelStep` entity and its branch list
```

## Acceptance criteria

- A workflow containing a static `parallel_step` compiles without transformer
  errors.
- `Spark.Dsl.Extension.get_entities(resource, [:workflow])` includes the
  `ParallelStep` entity.
- The introspected `ParallelStep` keeps its name, `on_complete`, completion
  strategy, and declared static branches.

## Notes

- **Reference / related code:**
  `lib/ash_jobs/dsl/entities/parallel_step.ex`,
  `lib/ash_jobs/transformers/integrate_state_machine.ex`
- **Size:** <= ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 01 — Green the ash_jobs test suite](../../../../../../docs/tasks/workflow-dag-engine/01-ash-jobs-test-cleanup.md) — restores static `parallel_step` compilation after the transformer regression.

## See also

- [US-SPS-02](US-SPS-02-completion-strategies.md) — the completion strategies
  preserved on those introspected entities.
- [US-RSB-05](../relationship-sourced-branches/US-RSB-05-static-branch-backcompat.md)
  — the future relationship-sourced branch work must keep this static form
  compatible.
