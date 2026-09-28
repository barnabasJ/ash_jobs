# US-NGD-10 — The direct enqueue path honors the trigger's custom `where` before inserting a job

**User-type:** developer **Status:** spec

```gherkin
Given a resource whose workflow step carries a custom `where` predicate (a parent-state gate, a custom ready flag)
When the direct enqueue path runs — a create's initial trigger, a success push, or a manual resume — through `AshJobs.Readiness.run_trigger_if_ready/2`
And the row's state and needs are satisfied but the `where` evaluates false
Then no Oban job is inserted
And the row waits in `:pending` until a later readiness evaluation finds the `where` true
And when the `where` evaluates true, the direct path enqueues exactly one job whose real worker runs the row
```

## Acceptance criteria

- A row created through the real create action with a false custom `where`
  produces **zero** Oban jobs for its trigger (the create after-action
  consults the same expression the scheduler and worker use).
- A row created with a true custom `where` produces exactly one Oban job, and
  draining it through the real generated worker runs the row to its success
  terminal.
- `AshJobs.Readiness.run_trigger_if_ready/2` returns `:not_ready` — and
  inserts nothing — while the `where` is false, and enqueues once it turns
  true. Callers that cannot know the gate state (pushes, resumes) can invoke
  it unconditionally without creating cancel-churn rows.
- No predicate logic is duplicated: the check evaluates the trigger's own
  generated `where` expression with a bounded single-row `exists?` read.

## Notes

- **Why:** `AshOban.run_trigger/2` builds the job from the record's primary
  key and never evaluates `trigger.where` — that expression gates the
  scheduler's scan and the worker's re-read only. Every direct enqueue
  (create-time first trigger, `push_dependents` on success, manual resume)
  therefore inserted jobs that the worker immediately cancelled with
  `:trigger_no_longer_applies` whenever a `where` gate was closed. Honoring
  the `where` at enqueue time removes the churn and makes the direct path
  equivalent to the paths it feeds.
- **Reference / related code:** `lib/ash_jobs/readiness.ex`
  (`run_trigger_if_ready/2`, `where_applies?/2`),
  `lib/ash_jobs/change.ex` (`handle_create_action/2`,
  `push_dependents` callers), `test/integration/where_gated_create_test.exs`.
- **Relation to US-NGD-07:** US-NGD-07 promises a row with unmet needs never
  self-starts on create; this story adds the stronger enqueue-time guarantee
  for the custom `where` half of the same generated predicate.

## See also

- [US-NGD-07](./US-NGD-07-unmet-needs-no-self-start.md) — the unmet-needs
  create guard this story extends to custom `where` predicates.
