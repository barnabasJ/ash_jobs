defmodule AshJobs.Dsl.Entities.BranchTest do
  use ExUnit.Case, async: true

  alias AshJobs.Dsl.Entities.Branch

  describe "struct" do
    test "has correct fields" do
      branch = %Branch{
        name: :payment,
        resource: SomeModule
      }

      assert branch.name == :payment
      assert branch.resource == SomeModule
    end

    test "defaults to nil for optional fields" do
      branch = %Branch{}

      assert branch.name == nil
      assert branch.resource == nil
      assert branch.__spark_metadata__ == nil
    end
  end

  describe "schema/0" do
    test "returns expected options" do
      schema = Branch.schema()

      assert Keyword.has_key?(schema, :name)
      assert Keyword.has_key?(schema, :resource)
      assert Keyword.has_key?(schema, :relationship)
      assert Keyword.has_key?(schema, :needs)

      assert schema[:name][:type] == :atom
      assert schema[:name][:required] == true

      # `resource` is optional: relationship-sourced (dynamic) branches declare a
      # `relationship` instead of a fixed resource (US-RSB-03).
      assert schema[:resource][:type] == :atom
      assert schema[:resource][:required] == false

      assert schema[:relationship][:type] == :atom
      assert schema[:relationship][:required] == false

      assert schema[:needs][:type] == :atom
      assert schema[:needs][:required] == false
    end
  end

  describe "args/0" do
    test "returns [:name, {:optional, :resource}]" do
      # `resource` is an optional positional arg so dynamic branches can omit it.
      assert Branch.args() == [:name, {:optional, :resource}]
    end
  end

  describe "target/0" do
    test "returns the module" do
      assert Branch.target() == Branch
    end
  end
end
