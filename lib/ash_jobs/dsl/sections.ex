defmodule AshJobs.Dsl.Sections do
  @moduledoc """
  DSL section definitions for AshJobs workflows.

  Defines the top-level `workflow` section that contains workflow configuration
  and step definitions.
  """

  alias AshJobs.Dsl.Entities.Step

  @doc """
  Defines the workflow section.

  A resource can have one workflow, which contains a series of steps that execute sequentially.

  ## Options

  - `:state_attribute` (atom) - Attribute to use for tracking workflow state (defaults to :state)

  ## Examples

      workflow do
        state_attribute :workflow_state  # Optional override

        step :load_order do
          action :load_full_order
          on_success :validate_inventory
          on_error :handle_load_error
        end

        step :validate_inventory do
          action :check_inventory
          on_success :create_shipment
          on_error :notify_inventory_error
        end
      end
  """
  def workflow do
    %Spark.Dsl.Section{
      name: :workflow,
      top_level?: false,
      schema: [
        state_attribute: [
          type: :atom,
          default: :state,
          doc: "Attribute to use for tracking workflow state"
        ]
      ],
      entities: [
        %Spark.Dsl.Entity{
          name: :step,
          target: Step,
          args: [:name],
          schema: Step.schema(),
          describe: "Defines a step in the workflow"
        }
      ],
      describe: """
      Defines a sequential workflow with explicit step routing.

      One workflow per resource, aligned with ash_state_machine's one-state-machine-per-resource design.
      """
    }
  end
end
