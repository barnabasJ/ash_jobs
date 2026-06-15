# US-RSB-02 — The branch passes its relationship/needs through to the state-machine region

**User-type:** developer **Status:** spec

```gherkin
Given a `parallel_step` containing a relationship-sourced `branch :jobs, relationship: :jobs`
When the AshJobs transformers run during compilation
Then the generated `parallel_region` carries a `region` built from the `:jobs` relationship source rather than a fixed `resource`
```

## Acceptance criteria

- For a relationship-sourced branch, `add_parallel_region/2` forwards
  `:relationship` (and any `needs` gating) to the region instead of
  `name:`/`resource:`.
- The region is built via the same `build_entity` call against
  `[:state_machine, :parallel_regions, :parallel_region]`.

## Notes

- **Reference / related code:**
  `packages/ash_jobs/lib/ash_jobs/transformers/integrate_parallel_regions.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 10 — Transformer passthrough](../../../../../../docs/tasks/workflow-dag-engine/10-transformer-passthrough.md) — the work that makes this story true.

## See also

- [US-RSB-01](US-RSB-01-declare-relationship-branch.md) — declares the
  relationship-sourced branch whose source this story passes through to the
  region.
