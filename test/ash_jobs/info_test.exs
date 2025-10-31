defmodule AshJobs.InfoTest do
  use ExUnit.Case, async: false

  import AshJobs.Test.CompilationHelpers

  setup do
    {:ok, resource} =
      compile_resource("""
        workflow do
          state_attribute :state

          step :load_order do
            action :load_order
            on_success :validate_inventory
            on_error :handle_error
            queue :order_processing
          end

          step :validate_inventory do
            action :validate
            on_success :completed
            queue :inventory_processing
          end
        end

        actions do
          defaults [:read]
          update :load_order, do: accept([])
          update :validate, do: accept([])
        end
      """)

    {:ok, resource: resource}
  end

  describe "workflow!/1" do
    test "returns workflow configuration", %{resource: resource} do
      workflow = AshJobs.Info.workflow!(resource)

      assert workflow
      assert workflow.state_attribute == :state
      assert length(workflow.steps) == 2
    end

    test "raises if no workflow defined" do
      {:ok, no_workflow_resource} =
        compile_resource("""
          actions do
            defaults [:read]
          end
        """)

      assert_raise RuntimeError, fn ->
        AshJobs.Info.workflow!(no_workflow_resource)
      end
    end
  end

  describe "workflow/1" do
    test "returns {:ok, workflow} when defined", %{resource: resource} do
      assert {:ok, workflow} = AshJobs.Info.workflow(resource)
      assert workflow.state_attribute == :state
    end

    test "returns :error if no workflow defined" do
      {:ok, no_workflow_resource} =
        compile_resource("""
          actions do
            defaults [:read]
          end
        """)

      assert :error = AshJobs.Info.workflow(no_workflow_resource)
    end
  end

  describe "steps/1" do
    test "returns list of workflow steps", %{resource: resource} do
      steps = AshJobs.Info.steps(resource)

      assert length(steps) == 2
      assert Enum.any?(steps, &(&1.name == :load_order))
      assert Enum.any?(steps, &(&1.name == :validate_inventory))
    end
  end

  describe "step/2" do
    test "returns step by name", %{resource: resource} do
      {:ok, step} = AshJobs.Info.step(resource, :load_order)

      assert step.name == :load_order
      assert step.action == :load_order
      assert step.on_success == :validate_inventory
      assert step.on_error == :handle_error
      assert step.queue == :order_processing
    end

    test "returns :error for nonexistent step", %{resource: resource} do
      assert :error = AshJobs.Info.step(resource, :nonexistent)
    end
  end

  describe "get_step_for_action/2" do
    test "returns step that uses given action", %{resource: resource} do
      {:ok, step} = AshJobs.Info.get_step_for_action(resource, :load_order)

      assert step.name == :load_order
      assert step.action == :load_order
    end

    test "returns :error if no step uses action", %{resource: resource} do
      assert :error = AshJobs.Info.get_step_for_action(resource, :nonexistent)
    end
  end

  describe "state_attribute/1" do
    test "returns state attribute name", %{resource: resource} do
      assert AshJobs.Info.state_attribute(resource) == :state
    end

    test "returns default :state if not specified" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :test_step do
              action :test_action
              on_success :completed
            end
          end

          actions do
            defaults [:read]
            update :test_action, do: accept([])
          end
        """)

      assert AshJobs.Info.state_attribute(resource) == :state
    end
  end

  describe "entry_points/1" do
    test "returns steps with no incoming references", %{resource: resource} do
      entry_points = AshJobs.Info.entry_points(resource)

      assert length(entry_points) == 1
      assert List.first(entry_points).name == :load_order
    end
  end

  describe "terminal_steps/1" do
    test "returns steps that transition to terminal states", %{resource: resource} do
      terminal_steps = AshJobs.Info.terminal_steps(resource)

      # validate_inventory transitions to :completed
      assert length(terminal_steps) == 1
      assert List.first(terminal_steps).name == :validate_inventory
    end
  end
end
