# US-RSB-03 — `resource` is not required when a relationship source is given

**User-type:** developer **Status:** spec

```gherkin
Given a `branch :jobs, relationship: :jobs` with no `resource` option supplied
When the DSL is compiled
Then no "required option :resource" error is raised and the branch is accepted with the relationship as its source
```

## Acceptance criteria

- Exactly one of `:resource` or `:relationship` is required on a branch —
  neither "both" nor "neither" compiles.
- A relationship-sourced branch with `:relationship` and no `:resource` compiles
  without a "required option :resource" error.

## Notes

- **Reference / related code:**
  `packages/ash_jobs/lib/ash_jobs/dsl/entities/branch.ex`,
  `packages/ash_jobs/lib/ash_jobs/verifiers/verify_parallel_steps.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 09 — Relationship-sourced branch](../../../../../../docs/tasks/workflow-dag-engine/09-relationship-sourced-branch.md) — the work that makes this story true.

## See also

- [US-RSB-01](US-RSB-01-declare-relationship-branch.md) — declares the
  relationship-sourced branch this story lets compile without a `:resource`.
