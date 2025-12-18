defmodule AshJobs.Dsl.Entities.Branch do
  @moduledoc """
  Defines a branch within a parallel_step.

  A branch references an external Ash resource that uses AshJobs
  and runs as a parallel workflow.

  ## Options

  - `:name` (atom, required) - Unique identifier for this branch (used as relationship name)
  - `:resource` (module, required) - Ash resource module implementing the branch workflow

  ## Examples

      parallel_step :process_parallel do
        completion_strategy :all
        on_complete :finalize

        branch :payment, PaymentWorkflow
        branch :inventory, InventoryWorkflow
      end

  The branch resource must:
  - Use the AshJobs extension
  - Have a `parent_id` attribute for the relationship back to the parent
  - Have terminal states (:completed, :failed) for completion detection
  """

  @type t :: %__MODULE__{
          name: atom(),
          resource: module(),
          __spark_metadata__: any()
        }

  defstruct [:name, :resource, :__spark_metadata__]

  def schema do
    [
      name: [
        type: :atom,
        required: true,
        doc: "Unique identifier for this branch (used as relationship name)"
      ],
      resource: [
        type: :atom,
        required: true,
        doc: "Ash resource module implementing the branch workflow (must use AshJobs)"
      ]
    ]
  end

  def args, do: [:name, :resource]

  def target, do: __MODULE__
end
