defmodule AshJobs.Dsl.SectionsTest do
  use ExUnit.Case, async: true

  alias AshJobs.Dsl.Sections

  describe "workflow section" do
    test "defines top-level workflow section" do
      section = Sections.workflow()
      assert section.name == :workflow
    end

    test "workflow section accepts state_attribute option" do
      section = Sections.workflow()
      schema = section.schema
      assert Keyword.has_key?(schema, :state_attribute)
      assert schema[:state_attribute][:default] == :state
    end

    test "workflow section has step entities" do
      section = Sections.workflow()
      step_entity = Enum.find(section.entities, fn entity -> entity.name == :step end)
      assert step_entity
      assert step_entity.target == AshJobs.Dsl.Entities.Step
    end

    test "workflow section is top-level (not nested)" do
      section = Sections.workflow()
      assert section.top_level? == true
    end
  end
end
