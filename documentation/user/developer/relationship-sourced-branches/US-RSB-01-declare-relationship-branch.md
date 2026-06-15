# US-RSB-01 — Declare a `branch` sourced from a relationship instead of a fixed resource

**User-type:** developer **Status:** spec

```gherkin
Given a workflow resource using the AshJobs extension with a `:jobs` relationship to a branch-workflow resource
When I declare `parallel_step :run_jobs do branch :jobs, relationship: :jobs end`
Then the DSL compiles and the branch records its source as the `:jobs` relationship rather than a fixed `resource` module
```

## Acceptance criteria

- The `branch` entity accepts a `:relationship` option alongside `:resource`.
- When `:relationship` is supplied, the compiled branch carries the relationship
  atom as its source instead of a target module.

## Notes

- **Reference / related code:**
  `packages/ash_jobs/lib/ash_jobs/dsl/entities/branch.ex`,
  `packages/ash_jobs/lib/ash_jobs/dsl/sections.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 09 — Relationship-sourced branch](../../../../../../docs/tasks/workflow-dag-engine/09-relationship-sourced-branch.md) — the work that makes this story true.

## See also

- [US-RSB-02](US-RSB-02-passthrough-to-region.md) — carries the relationship
  source declared here through to the generated parallel region.
- [US-RSB-03](US-RSB-03-resource-not-required.md) — relaxes the `:resource`
  requirement so this relationship-sourced declaration compiles.
- [US-RSB-05](US-RSB-05-static-branch-backcompat.md) — contrasts this with the
  static `branch :name, Resource` form that still works unchanged.
