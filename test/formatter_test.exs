defmodule AshJobs.FormatterTest do
  use ExUnit.Case

  test "formatter recognizes Spark DSL keywords" do
    # Verify .formatter.exs imports Spark plugin
    formatter_opts = Code.eval_file(".formatter.exs") |> elem(0)
    plugins = Keyword.get(formatter_opts, :plugins, [])
    assert Spark.Formatter in plugins

    # Verify import_deps includes ash libraries
    import_deps = Keyword.get(formatter_opts, :import_deps, [])
    assert :ash in import_deps
    assert :ash_state_machine in import_deps
    assert :ash_oban in import_deps
  end
end
