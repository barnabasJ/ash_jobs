# US-CYC-02 — A detected cycle fails the parent region with a clear error

**User-type:** developer **Status:** spec

```gherkin
Given the runtime DAG check has detected a cycle in the fanned-out rows'
  `needs` edges
When fan-out resolves the activation changeset
Then the parent region transitions to a failure state and the operation returns
  a clear, named error identifying the cycle (the rows / edges involved) — not a
  generic timeout, a silent hang, or an opaque internal error
```

## Acceptance criteria

- A detected cycle fails the parent region instead of creating or scheduling
  rows.
- The returned error is a dedicated, named cycle error identifying the offending
  rows/edges — not a generic timeout or opaque internal error.

## Notes

- **Reference / related code:**
  `lib/ash_state_machine/lib/builtin_changes/activate_parallel_regions.ex`
  (`create_region_resources/3` folds a region-creation `{:error, _}` back
  through the `after_action` hook to fail the parent changeset) and a planned
  ash_jobs cycle helper under `packages/ash_jobs/lib/ash_jobs/`.
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 18 — Cycle detection](../../../../../../docs/tasks/workflow-dag-engine/18-cycle-detection.md) — the work that makes this story true.

## See also

- [US-CYC-01](US-CYC-01-detect-cycle-on-fan-out.md) — the detection step this
  failure path reacts to: the cycle is caught at fan-out.
- [US-CYC-03](../../security-engineer/cycle-detection/US-CYC-03-bound-execution-no-exhaustion.md)
  — the security view: failing fast keeps a malformed graph from exhausting
  resources.
