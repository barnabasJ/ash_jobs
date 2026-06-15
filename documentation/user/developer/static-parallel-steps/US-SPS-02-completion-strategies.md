# US-SPS-02 — Static completion strategies are retained and validated

**User-type:** developer **Status:** spec

```gherkin
Given a workflow author declares a fixed-resource `parallel_step` with `:all`, `:any`, or `{:require_n, n}` completion
When the workflow DSL compiles
Then the `ParallelStep` stores the chosen completion strategy
And `{:require_n, n}` remains bounded by the number of static branches
```

## Acceptance criteria

- Static `parallel_step` accepts `:all`, `:any`, and `{:require_n, n}` completion
  strategy values.
- The compiled `ParallelStep` exposes the configured strategy through Spark
  introspection.
- Static branch behavior remains separate from the future dynamic relationship
  form, where the `require_n` bound is resolved at runtime.

## Notes

- **Reference / related code:**
  `lib/ash_jobs/dsl/entities/parallel_step.ex`,
  `lib/ash_jobs/verifiers/verify_parallel_steps.ex`
- **Size:** <= ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 01 — Green the ash_jobs test suite](../../../../../../docs/tasks/workflow-dag-engine/01-ash-jobs-test-cleanup.md) — restores static completion-strategy compilation coverage after the transformer regression.

## See also

- [US-SPS-01](US-SPS-01-fixed-branches-compile.md) — static branch compilation
  and introspection.
- [US-RSB-04](../relationship-sourced-branches/US-RSB-04-require-n-runtime.md)
  — the dynamic branch case that moves the bound to runtime.
