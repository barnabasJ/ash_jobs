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

      assert schema[:name][:type] == :atom
      assert schema[:name][:required] == true

      assert schema[:resource][:type] == :atom
      assert schema[:resource][:required] == true
    end
  end

  describe "args/0" do
    test "returns [:name, :resource]" do
      assert Branch.args() == [:name, :resource]
    end
  end

  describe "target/0" do
    test "returns the module" do
      assert Branch.target() == Branch
    end
  end
end
