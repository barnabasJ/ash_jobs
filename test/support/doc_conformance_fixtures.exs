# SPDX-License-Identifier: MIT
#
# Compiled fixture modules for the doc-conformance gate tests
# (`test/doc_conformance_test.exs`, stories US-DOC-01..US-DOC-03). The
# `StoryTraceability` engine inspects the **resolved ExUnit registry**
# (`module.__ex_unit__/0`), so the fixtures must be real `ExUnit.Case` modules,
# not source snippets. They are `Code.require_file/1`-loaded by the test and
# tagged `@moduletag :st_fixture` so the suite excludes them from running (see
# `test/test_helper.exs`). Their `US-DOCFIX-*` ids are deliberately NOT real
# stories — they only ever pair with the throwaway doc fixtures each test
# builds in a temp dir, never the real `documentation/**/US-*.md` tree.
defmodule AshJobs.DocConformanceFixtures.TaggedAndUntagged do
  @moduledoc "One story-tagged test and one test with no `@tag story:`."
  use ExUnit.Case, async: true
  @moduletag :st_fixture

  @tag story: "US-DOCFIX-01"
  test "tagged" do
    assert true
  end

  test "untagged" do
    assert true
  end
end

defmodule AshJobs.DocConformanceFixtures.UnknownTag do
  @moduledoc "A `@tag story:` naming a story id with no `US-*.md` file behind it."
  use ExUnit.Case, async: true
  @moduletag :st_fixture

  @tag story: "US-DOCFIX-99"
  test "names a non-existent story" do
    assert true
  end
end
