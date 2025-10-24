defmodule AshJobsTest do
  use ExUnit.Case
  doctest AshJobs

  test "project compiles with all dependencies" do
    # Verify dependencies are loadable
    assert Code.ensure_loaded?(Ash.Resource)
    assert Code.ensure_loaded?(Spark.Dsl.Extension)
    assert Code.ensure_loaded?(AshStateMachine)
    assert Code.ensure_loaded?(AshOban)
    assert Code.ensure_loaded?(Oban)
  end
end
