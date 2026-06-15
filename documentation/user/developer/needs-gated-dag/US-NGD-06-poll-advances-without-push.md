# US-NGD-06 — With push disabled, the scheduler poll still advances ready rows

**User-type:** developer **Status:** spec

```gherkin
Given push readiness is disabled for the workflow
And row D `needs` row A, and A has reached a success state
When the scheduler's periodic poll next runs
Then it evaluates D's readiness where, finds it satisfied, and enqueues D
And D advances even though no success push notified it
```

## Acceptance criteria

- The generated Oban scheduler periodically scans rows whose state matches a
  trigger and re-checks the readiness `where`, picking up a row whose needs are
  all in success on the next poll regardless of whether a push fired.
- Readiness is eventually-consistent: even if a push is dropped or disabled, no
  ready row is stranded — the poll is the backstop.

## Notes

- **Reference / related code:** `lib/ash_jobs/transformers/integrate_oban.ex`
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 14 — Push on completion](../../../../../../docs/tasks/workflow-dag-engine/14-push-on-completion.md) — the work that makes this story true.

## See also

- [US-NGD-03](US-NGD-03-start-after-all-needs-success.md) — the readiness gate
  the poll re-evaluates each scan.
- [US-NGD-05](US-NGD-05-success-pushes-dependents-ready.md) — the success push
  this poll backstops when push is disabled or dropped.
