# US-RSB-06 — A relationship-sourced parallel step finalizes its parent when its branches complete

**User-type:** developer **Status:** spec

```gherkin
Given a workflow whose `parallel_step` fans out over a `relationship` (a dynamic region) with `triggers true`
When every fanned-out branch row reaches a success terminal state
Then a generated parent completion trigger transitions the parent into its `on_complete` state on its own — no manual `check_parallel_completion` call
And if any branch row reaches a failure terminal state, the parent is routed to its `on_error` state instead
```

## Acceptance criteria

- A dynamic `parallel_step` with `triggers true` generates a parent-side
  completion trigger whose `where` is gated on the branch rows being terminal
  (the same `exists` pattern the needs gate uses): complete once no branch is
  outside a success terminal, errored once any branch reached a failure
  terminal.
- When the trigger fires, the parent transitions to its `on_complete`
  (`handle_<region>_complete`) or `on_error` (`handle_<region>_error`) state —
  so a real run drives the parent to a terminal state without a manual
  completion check.
- The generated error trigger and transition include every declared parent
  initial state, so a child failure can reconcile a parent before it enters the
  dynamic region state.

## Notes

- **Reference / related code:**
  `packages/ash_jobs/lib/ash_jobs/transformers/integrate_oban.ex`
  (`generate_dynamic_completion_triggers`),
  `packages/ash_jobs/lib/ash_jobs/transformers/integrate_state_machine.ex`
  (generated error-transition source states).
- Static regions are driven instead through the parent's generated
  `DelegateToRegion` wrapper actions (`GenerateRegionActions`); dynamic regions
  skip those, which is why they need this completion trigger.

## See also

- [US-RSB-02](US-RSB-02-passthrough-to-region.md) — the branch passes its
  relationship through to the region this trigger then finalizes.
- [US-DPR-03](../../../../../ash_state_machine/documentation/user/developer/dynamic-parallel-regions/US-DPR-03-all-completion-succeeds.md)
  — the coordinator's `:all` completion verdict this trigger acts on.
