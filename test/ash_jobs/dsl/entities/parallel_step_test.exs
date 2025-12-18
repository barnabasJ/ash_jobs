defmodule AshJobs.Dsl.Entities.ParallelStepTest do
  use ExUnit.Case, async: true

  alias AshJobs.Dsl.Entities.ParallelStep

  describe "struct" do
    test "has correct fields" do
      parallel_step = %ParallelStep{
        name: :process_parallel,
        completion_strategy: :all,
        on_complete: :finalize,
        on_error: :handle_error,
        branches: []
      }

      assert parallel_step.name == :process_parallel
      assert parallel_step.completion_strategy == :all
      assert parallel_step.on_complete == :finalize
      assert parallel_step.on_error == :handle_error
      assert parallel_step.branches == []
    end

    test "default completion_strategy is :all" do
      parallel_step = %ParallelStep{name: :test, on_complete: :done}

      assert parallel_step.completion_strategy == :all
    end

    test "default branches is empty list" do
      parallel_step = %ParallelStep{name: :test, on_complete: :done}

      assert parallel_step.branches == []
    end

    test "on_error defaults to nil" do
      parallel_step = %ParallelStep{name: :test, on_complete: :done}

      assert parallel_step.on_error == nil
    end
  end

  describe "schema/0" do
    test "returns expected options" do
      schema = ParallelStep.schema()

      assert Keyword.has_key?(schema, :name)
      assert Keyword.has_key?(schema, :completion_strategy)
      assert Keyword.has_key?(schema, :on_complete)
      assert Keyword.has_key?(schema, :on_error)

      # name is required atom
      assert schema[:name][:type] == :atom
      assert schema[:name][:required] == true

      # on_complete is required atom
      assert schema[:on_complete][:type] == :atom
      assert schema[:on_complete][:required] == true

      # on_error is optional atom
      assert schema[:on_error][:type] == :atom
      assert schema[:on_error][:required] == false

      # completion_strategy default is :all
      assert schema[:completion_strategy][:default] == :all
    end

    test "completion_strategy accepts :all" do
      schema = ParallelStep.schema()
      type = schema[:completion_strategy][:type]

      # The type should be an :or type that includes {:in, [:all, :any]}
      assert {:or, options} = type
      assert {:in, [:all, :any]} in options
    end

    test "completion_strategy accepts {:require_n, count}" do
      schema = ParallelStep.schema()
      type = schema[:completion_strategy][:type]

      # The type should include {:tuple, [{:literal, :require_n}, :pos_integer]}
      assert {:or, options} = type
      assert {:tuple, [{:literal, :require_n}, :pos_integer]} in options
    end
  end

  describe "args/0" do
    test "returns [:name]" do
      assert ParallelStep.args() == [:name]
    end
  end

  describe "target/0" do
    test "returns the module" do
      assert ParallelStep.target() == ParallelStep
    end
  end
end
