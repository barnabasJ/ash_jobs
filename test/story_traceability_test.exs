defmodule AshJobs.StoryTraceabilityTest do
  @moduledoc """
  The story↔test traceability gate for `ash_jobs`. Each user story is its own
  file under `documentation/user/<user-type>/<feature>/US-*.md` (with a
  Given/When/Then); the tests that exercise it reference it with `@tag story:`.
  The shared `StoryTraceability.SuiteCheck` ratchets two numbers — package tests
  with no story tag, and documented stories with no test — so coverage can only
  hold or improve.

  This is the package-local adoption of the repo's documentation-conformance
  pattern (see `documentation/user/qa-engineer/doc-conformance/`). The baselines
  self-initialize on the first run and are committed thereafter.
  """
  use StoryTraceability.SuiteCheck,
    docs: "documentation/**/US-*.md",
    tests: "test/**/*_test.exs",
    baseline_dir: "test"
end
