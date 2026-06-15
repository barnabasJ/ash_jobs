# US-NGD-01 — Declare a `needs` dependency between sibling rows

**User-type:** developer **Status:** spec

```gherkin
Given a workflow whose rows are fanned out from a relationship
When I declare that row B `needs` row A by pointing B's needs edge at A
Then the edge is persisted as a self-referential relationship between the sibling rows
And the readiness gate for B will consult A's state before B can advance
```

## Acceptance criteria

- A `needs` edge is persisted as a self-referential relationship between sibling
  rows of the same fanned-out set, recorded as plain application data (not a DSL
  construct).
- Declaring the edge does not change the row's own create or state attribute.
- The generated readiness `where` joins across the relationship so the dependent
  row's trigger only matches once the edge target reaches a success state.

## Notes

- **Reference / related code:** `lib/ash_jobs/transformers/integrate_oban.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 12 — needs edge DSL](../../../../../../docs/tasks/workflow-dag-engine/12-needs-edge-dsl.md) — the work that makes this story true.

## See also

- [US-NGD-02](US-NGD-02-no-needs-ready-immediately.md) — what a row's readiness
  looks like when it declares no `needs` edge.
- [US-NGD-03](US-NGD-03-start-after-all-needs-success.md) — how a declared edge
  gates the dependent row until its needs reach success.
- [US-NGD-09](../../agent/needs-gated-dag/US-NGD-09-ordering-via-needs-not-sort-order.md)
  — authoring ordering with `needs` edges instead of a global `sort_order`.
