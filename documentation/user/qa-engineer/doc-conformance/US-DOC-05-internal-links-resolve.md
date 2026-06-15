# US-DOC-05 — Internal documentation links resolve (lychee offline)

**User-type:** qa-engineer **Status:** spec

```gherkin
Given the ash_jobs documentation tree with internal links between docs
When lychee runs in offline mode over the docs
Then every internal link resolves to an existing file or anchor, and a broken internal link fails the Docs links CI check
```

## Acceptance criteria

- Run offline, lychee verifies every relative link between docs points at a file
  and anchor that exists.
- A moved or misspelled internal path fails the Docs links CI check instead of
  rotting silently.

## Notes

- **Reference / related code:** `lychee.toml`, the Docs links CI workflow
  `.github/workflows/docs-links.yml`.
- **Size:** ≤ ~200 lines, 1 module — else split into subtasks.

## Tasks

- [Task 23 — Doc-conformance gate](../../../../../../docs/tasks/workflow-dag-engine/23-doc-conformance-gate.md) — the work that makes this story true.
