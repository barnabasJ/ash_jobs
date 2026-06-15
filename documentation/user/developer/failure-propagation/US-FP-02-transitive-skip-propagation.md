# US-FP-02 — Skips propagate transitively across the `needs` graph

**User-type:** developer **Status:** spec

```gherkin
Given a chain A ← B ← C where B `needs` A and C `needs` B
When A transitions into its `:failed` state
Then B is transitioned to `:skipped` and C is also transitioned to `:skipped`
```

## Acceptance criteria

- Skipping a row is treated as a new gating-failure that continues the walk.
- The entire transitive reverse-`needs` closure reaches `:skipped`.
- No Oban jobs are re-triggered for skipped rows.

## Notes

- **Reference / related code:** `packages/ash_jobs/lib/ash_jobs/change.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 16 — :skipped state + propagation](../../../../../../docs/tasks/workflow-dag-engine/16-skip-state-and-propagation.md) — the work that makes this story true.

## See also

- [US-FP-01](US-FP-01-direct-dependents-skipped.md) — the single-hop skip this
  propagates transitively.
- [US-FP-03](US-FP-03-skipped-terminal-state.md) — adds the `:skipped` terminal
  state each propagated row reaches.
- [US-FP-05](../../operator/failure-propagation/US-FP-05-dependents-never-stuck-pending.md)
  — operator-facing guarantee that the whole closure resolves, never stuck
  pending.
