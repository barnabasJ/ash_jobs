# US-NGD-08 — Independent rows are observably concurrent in a run

**User-type:** operator **Status:** spec

```gherkin
Given a workflow run with several rows that share no `needs` edges
When the run executes
Then the independent rows' step actions overlap in time
And the run's timeline shows them in-progress concurrently, not strictly serialized
```

## Acceptance criteria

- Rows with no `needs` chain between them are enqueued together and execute on
  Oban workers in parallel, bounded only by queue concurrency.
- The run's observable timeline reflects the declared DAG — serialized only
  along `needs` edges, concurrent everywhere else.

## Notes

- **Reference / related code:** `lib/ash_jobs/transformers/integrate_oban.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 14 — Push on completion](../../../../../../docs/tasks/workflow-dag-engine/14-push-on-completion.md) — the work that makes this story true.

## See also

- [US-NGD-04](../../developer/needs-gated-dag/US-NGD-04-independent-rows-parallel.md)
  — the developer-level mechanism behind this observable concurrency.
