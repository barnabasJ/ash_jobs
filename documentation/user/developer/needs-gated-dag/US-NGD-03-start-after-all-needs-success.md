# US-NGD-03 — A row starts only once all its `needs` reach a success state

**User-type:** developer **Status:** spec

```gherkin
Given row C that `needs` both row A and row B
And A is in a success state but B is not
When the scheduler evaluates C's readiness where
Then C does not match its trigger and stays :pending
When B also reaches a success state
Then C's readiness where is satisfied and C advances out of :pending
```

## Acceptance criteria

- Readiness is conjunctive: every edge target must be in a success state before
  the row advances.
- The gate is the per-step state filter `and`-combined with the edge clause via
  `combine_where_exprs/2`, reusing the combiner that merges a step's custom
  `where` with its state filter.
- The set of success states comes from `AshStateMachine.Info`'s terminal-state
  API, not a hardcoded atom.

## Notes

- **Reference / related code:** `lib/ash_jobs/transformers/integrate_oban.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 08 — Terminal-state Info API](../../../../../../docs/tasks/workflow-dag-engine/08-terminal-state-info-api.md) — the work that makes this story true.
- [Task 13 — Readiness where-filter](../../../../../../docs/tasks/workflow-dag-engine/13-readiness-where-filter.md) — the work that makes this story true.

## See also

- [US-NGD-01](US-NGD-01-declare-needs-edge.md) — declaring the `needs` edges
  whose success this gate consults.
- [US-NGD-04](US-NGD-04-independent-rows-parallel.md) — rows off the `needs`
  chain run in parallel rather than waiting on this gate.
- [US-NGD-05](US-NGD-05-success-pushes-dependents-ready.md) — how a need
  reaching success pushes the now-satisfied dependent to ready.
