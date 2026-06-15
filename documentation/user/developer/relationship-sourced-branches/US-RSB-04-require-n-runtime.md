# US-RSB-04 — `{:require_n, n}` is no longer rejected at compile time for a dynamic branch

**User-type:** developer **Status:** spec

```gherkin
Given a `parallel_step` with `completion_strategy {:require_n, 5}` and a relationship-sourced branch
When the DSL is compiled
Then the verifier does not reject `n` against the declared branch count, because the real branch count is only known at runtime
```

## Acceptance criteria

- For a relationship-sourced parallel_step, the `n > length(ps.branches)`
  upper-bound check is skipped.
- `n > 0` is still enforced at compile time; the upper-bound check moves to
  runtime.

## Notes

- **Reference / related code:**
  `packages/ash_jobs/lib/ash_jobs/verifiers/verify_parallel_steps.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 11 — require_n at runtime](../../../../../../docs/tasks/workflow-dag-engine/11-require-n-runtime.md) — the work that makes this story true.

## See also

- [US-RSB-01](US-RSB-01-declare-relationship-branch.md) — declares the
  relationship-sourced branch whose runtime-only count makes this
  `{:require_n, n}` upper-bound check move to runtime.
