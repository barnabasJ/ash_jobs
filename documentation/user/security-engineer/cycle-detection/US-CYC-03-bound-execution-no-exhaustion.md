# US-CYC-03 — Cycle detection bounds execution (no infinite readiness re-evaluation / resource exhaustion)

**User-type:** security-engineer **Status:** spec

```gherkin
Given a malformed or adversarial `needs` graph (a cycle, or self-referential
  edges) supplied as app data on the fanned-out rows
When the parent region activates and fan-out runs the runtime DAG check
Then the check terminates in bounded time, fails the run fast, and the malformed
  graph never causes an unbounded scheduler poll loop, repeated readiness
  re-evaluation, or row/job creation that exhausts database or worker resources
```

## Acceptance criteria

- The DAG check terminates in bounded time on a cyclic or self-referential graph
  (single traversal, no unbounded recursion on a self-cycle).
- A malformed `needs` graph fails fast at activation and never escapes into the
  scheduler to drive an unbounded poll loop or resource-exhausting row/job
  creation.

## Notes

- **Reference / related code:**
  `lib/ash_state_machine/lib/builtin_changes/activate_parallel_regions.ex`
  (`create_region_resources/3` fan-out path) and a planned ash_jobs cycle helper
  under `packages/ash_jobs/lib/ash_jobs/`. The readiness `where`
  (`not exists(needs, state ∉ success)`) is the loop this check bounds.
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 18 — Cycle detection](../../../../../../docs/tasks/workflow-dag-engine/18-cycle-detection.md) — the work that makes this story true.

## See also

- [US-CYC-01](../../developer/cycle-detection/US-CYC-01-detect-cycle-on-fan-out.md)
  — the detection this story bounds: the DAG check that catches the cycle at
  fan-out.
- [US-CYC-02](../../developer/cycle-detection/US-CYC-02-fail-parent-region-clear-error.md)
  — the fail-fast behavior that keeps the malformed graph out of the scheduler.
