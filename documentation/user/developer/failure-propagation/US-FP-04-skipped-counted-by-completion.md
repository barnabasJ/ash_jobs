# US-FP-04 — Skipped rows are counted correctly by `:all` / `{:require_n}` completion

**User-type:** developer **Status:** spec

```gherkin
Given a parallel region group whose branches include a row that has been transitioned to `:skipped`
When `check_group_completion/3` evaluates the group under the `:all` or `{:require_n, count}` strategy
Then the skipped row is treated as a non-succeeding terminal outcome so the group resolves instead of hanging on `:pending`
```

## Acceptance criteria

- A `:skipped` row is classified as a terminal non-success, not `:pending`.
- `:all` sees the group as all-terminal and resolves.
- `{:require_n, count}` reaches its `pending_count == 0` resolution.

## Notes

- **Reference / related code:**
  `packages/ash_state_machine/lib/parallel_coordinator.ex`
  (`check_group_completion/3`, `region_status/2`,
  `get_success_terminal_states/1`, `terminal_failure_for_region?/2`)
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 06 — Coordinator counts rows](../../../../../../docs/tasks/workflow-dag-engine/06-coordinator-count-rows.md) — the work that makes this story true.
- [Task 17 — Skip completion counting](../../../../../../docs/tasks/workflow-dag-engine/17-skip-completion-counting.md) — the work that makes this story true.

## See also

- [US-FP-03](US-FP-03-skipped-terminal-state.md) — defines the `:skipped`
  terminal state this completion logic classifies as a non-success.
