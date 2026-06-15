# US-RSB-05 — A static `branch :name, Resource` still compiles and runs unchanged (back-compat)

**User-type:** developer **Status:** spec

```gherkin
Given an existing workflow using `branch :payment, PaymentWorkflow` with a fixed resource and no relationship option
When the DSL is compiled and the parallel_step runs
Then it behaves exactly as before — the same region with `resource: branch.resource` is generated and `{:require_n, n}` is still bounded by the static branch count
```

## Acceptance criteria

- When `:relationship` is absent, `:resource` remains required and the region is
  built with `name:`/`resource:` as before.
- The `n > length(ps.branches)` compile-time check still applies to
  `{:require_n, n}` for static branches.

## Notes

- **Reference / related code:**
  `packages/ash_jobs/lib/ash_jobs/dsl/entities/branch.ex`,
  `packages/ash_jobs/lib/ash_jobs/transformers/integrate_parallel_regions.ex`,
  `packages/ash_jobs/lib/ash_jobs/verifiers/verify_parallel_steps.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 09 — Relationship-sourced branch](../../../../../../docs/tasks/workflow-dag-engine/09-relationship-sourced-branch.md) — the work that makes this story true.

## See also

- [US-RSB-01](US-RSB-01-declare-relationship-branch.md) — the
  relationship-sourced declaration this static back-compat form is contrasted
  against.
