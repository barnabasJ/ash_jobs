# US-CYC-01 — A cyclic `needs` graph is detected at fan-out

**User-type:** developer **Status:** spec

```gherkin
Given a relationship-sourced branch whose fanned-out sibling rows carry `needs`
  edges that form a cycle (e.g. row A needs B, B needs C, C needs A)
When the parent transitions into the activating state and the regions are
  created on fan-out
Then the runtime DAG check over the `needs` edge set detects the cycle before
  any row is scheduled, rather than letting every row stay `:pending` waiting on
  a sibling that waits back
```

## Acceptance criteria

- A cyclic `needs` edge set is detected at fan-out, before any region row is
  scheduled or its readiness `where` is evaluated.
- Detection runs on the activation/fan-out path, not at compile time, because
  `needs` is runtime app data over sibling rows.

## Notes

- **Reference / related code:**
  `lib/ash_state_machine/lib/builtin_changes/activate_parallel_regions.ex`
  (`create_region_resources/3` `after_action` hook) and a planned ash_jobs cycle
  helper under `packages/ash_jobs/lib/ash_jobs/`.
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 18 — Cycle detection](../../../../../../docs/tasks/workflow-dag-engine/18-cycle-detection.md) — the work that makes this story true.

## See also

- [US-CYC-02](US-CYC-02-fail-parent-region-clear-error.md) — what happens once a
  cycle is detected: the parent region fails with a clear, named error.
- [US-CYC-03](../../security-engineer/cycle-detection/US-CYC-03-bound-execution-no-exhaustion.md)
  — the security view: detection must terminate in bounded time without resource
  exhaustion.
