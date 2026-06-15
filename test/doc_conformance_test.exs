# SPDX-License-Identifier: MIT
defmodule AshJobs.DocConformanceTest do
  @moduledoc """
  Behaviour tests for the `ash_jobs` doc-conformance gate — one test per
  `US-DOC-*` story under `documentation/user/qa-engineer/`. Each proves the
  exact Given/When/Then that the `StoryTraceability.SuiteCheck` wiring in
  `test/story_traceability_test.exs` (plus the `lychee` link check) makes true
  for this package.

  The test-side stories (US-DOC-01..03) are exercised against **compiled**
  fixture modules under `test/support/doc_conformance_fixtures.exs` — the engine
  reads the resolved ExUnit registry, not source. The story-quality story
  (US-DOC-04) and the ratchet behaviour use throwaway files in a temp dir, and
  the link-resolution story (US-DOC-05) runs `lychee --offline` over a temp doc
  tree.
  """
  use ExUnit.Case, async: true

  alias StoryTraceability.Coverage
  alias StoryTraceability.Ratchet

  @fixtures Path.expand("support/doc_conformance_fixtures.exs", __DIR__)

  setup_all do
    # Force-load the compiled fixture modules so the engine can read their
    # ExUnit registry. Idempotent: `Code.require_file/1` dedups by path.
    Code.require_file(@fixtures)
    :ok
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "ash_jobs_doc_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp write(dir, name, contents) do
    path = Path.join(dir, name)
    File.write!(path, contents)
    path
  end

  @tag story: "US-DOC-01"
  test "an untagged test is counted, and a new untagged test grows the count past the baseline",
       %{dir: dir} do
    # Given the suite with the SuiteCheck gate, the fixtures hold exactly one
    # `test` carrying no `@tag story:`.
    untagged = Coverage.untagged_tests([@fixtures])
    assert [{@fixtures, "untagged"}] = untagged

    # When that lone untagged test is baselined, the count holds clean at 1.
    baseline = Path.join(dir, "untagged.txt")
    assert {:initialized, 1} = Ratchet.check(length(untagged), baseline)
    assert :ok = Ratchet.check(1, baseline)

    # Then adding a new untagged test (2 > 1) grows the count past the baseline
    # and is a ratchet regression that fails the build.
    assert {:regressed, 1, 2} = Ratchet.check(2, baseline)
  end

  @tag story: "US-DOC-02"
  test "a story with no referencing test is counted, and a new untested story fails the build",
       %{dir: dir} do
    # Given two story files, where the fixtures tag US-DOCFIX-01 (not -02).
    write(dir, "US-DOCFIX-01-tagged.md", "Given\nWhen\nThen\n")
    write(dir, "US-DOCFIX-02-orphan.md", "Given\nWhen\nThen\n")

    # When the suite subtracts the referenced ids, -02 is the only story with no
    # referencing test.
    untested = Coverage.untested_stories([Path.join(dir, "*.md")], [@fixtures])
    assert ["US-DOCFIX-02"] = untested

    # Then that single untested story baselines clean at 1.
    baseline = Path.join(dir, "untested.txt")
    assert {:initialized, 1} = Ratchet.check(length(untested), baseline)

    # Then adding a second untested story (2 > 1) grows the count past the
    # baseline and is a regression that fails the build.
    assert {:regressed, 1, 2} = Ratchet.check(2, baseline)
  end

  @tag story: "US-DOC-03"
  test "a @tag story: naming a non-existent story is reported as undocumented (fails immediately)",
       %{dir: dir} do
    # Given only US-DOCFIX-01 is declared as a story file, while the fixtures
    # carry a `@tag story:` naming US-DOCFIX-99, which has no matching file.
    write(dir, "US-DOCFIX-01-tagged.md", "Given\nWhen\nThen\n")

    # When the suite collects tagged ids and checks each against the docs glob.
    undocumented = Coverage.undocumented_tags([Path.join(dir, "*.md")], [@fixtures])

    # Then the non-existent tag is reported as undocumented (the SuiteCheck
    # asserts this list is empty, so it fails immediately — not ratcheted),
    # while the real story id is not.
    assert "US-DOCFIX-99" in undocumented
    refute "US-DOCFIX-01" in undocumented
  end

  @tag story: "US-DOC-04"
  test "a story file with no Given/When/Then is reported incomplete", %{dir: dir} do
    # Given two story files: one spelling out a full Given/When/Then, and one
    # hollow stub with just a title and no scenario outline.
    complete =
      write(
        dir,
        "US-DOCFIX-01-ok.md",
        "# US-DOCFIX-01\n\nGiven a thing\nWhen it runs\nThen done\n"
      )

    stub = write(dir, "US-DOCFIX-02-stub.md", "# US-DOCFIX-02\n\njust a title, no outline\n")

    # When the suite parses each story file for a Given/When/Then.
    incomplete = Coverage.incomplete_stories([Path.join(dir, "*.md")])

    # Then the stub is reported incomplete (failing the gate) while the
    # complete story is not.
    assert stub in incomplete
    refute complete in incomplete
  end

  @tag story: "US-DOC-05"
  test "lychee offline flags a broken internal link and passes a resolving one", %{dir: dir} do
    # Given a docs tree with internal links — one relative link to an existing
    # file, and one to a missing file — and lychee available to scan it.
    lychee = System.find_executable("lychee")
    assert lychee, "lychee must be installed (mise-managed) to run the offline link check"

    write(dir, "target.md", "# Target\n")
    ok_doc = write(dir, "resolves.md", "[target](./target.md)\n")
    broken_doc = write(dir, "broken.md", "[missing](./missing.md)\n")

    # When lychee runs in offline mode over each doc.
    run = fn doc ->
      {_out, status} =
        System.cmd(lychee, ["--offline", "--no-progress", doc], stderr_to_stdout: true)

      status
    end

    # Then the link to an existing file resolves — lychee exits 0.
    assert run.(ok_doc) == 0

    # Then the link to a missing file is a broken internal link — lychee exits
    # non-zero, which fails the Docs links CI check.
    assert run.(broken_doc) != 0
  end
end
