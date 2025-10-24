defmodule AshJobs.Dsl.Entities.StepTest do
  use ExUnit.Case, async: true

  alias AshJobs.Dsl.Entities.Step

  describe "Step entity schema" do
    test "defines required :name option" do
      schema = Step.schema()
      assert Keyword.has_key?(schema, :name)
      assert schema[:name][:required] == true
    end

    test "defines :action option" do
      schema = Step.schema()
      assert Keyword.has_key?(schema, :action)
    end

    test "defines :on_success option" do
      schema = Step.schema()
      assert Keyword.has_key?(schema, :on_success)
    end

    test "defines :on_error option" do
      schema = Step.schema()
      assert Keyword.has_key?(schema, :on_error)
    end

    test "defines optional :queue option" do
      schema = Step.schema()
      assert Keyword.has_key?(schema, :queue)
      assert schema[:queue][:required] == false
    end

    test "defines optional :trigger option (defaults to true)" do
      schema = Step.schema()
      assert Keyword.has_key?(schema, :trigger)
      assert schema[:trigger][:default] == true
    end
  end

  describe "Step entity args" do
    test "accepts name as first positional argument" do
      args = Step.args()
      assert :name in args
    end
  end

  describe "Step entity target" do
    test "targets AshJobs.Dsl.Entities.Step module" do
      assert Step.target() == Step
    end
  end
end
