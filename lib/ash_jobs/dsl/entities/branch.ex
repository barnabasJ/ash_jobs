defmodule AshJobs.Dsl.Entities.Branch do
  @moduledoc """
  Defines a branch within a parallel_step.

  A branch references either a fixed Ash resource that uses AshJobs or a parent
  relationship whose related rows are runtime branch instances.

  ## Options

  - `:name` (atom, required) - Unique identifier for this branch (used as relationship name)
  - `:resource` (module) - Ash resource module implementing a static branch workflow
  - `:relationship` (atom) - Parent has_many relationship for dynamic branches
  - `:needs` (atom) - Relationship on dynamic branch rows listing prerequisite rows

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
          resource: module() | nil,
          relationship: atom() | nil,
          needs: atom() | nil,
          __spark_metadata__: any()
        }

  defstruct [:name, :resource, :relationship, :needs, :__spark_metadata__]

  def schema do
    [
      name: [
        type: :atom,
        required: true,
        doc: "Unique identifier for this branch (used as relationship name)"
      ],
      resource: [
        type: :atom,
        required: false,
        doc: "Ash resource module implementing a static branch workflow (must use AshJobs)"
      ],
      relationship: [
        type: :atom,
        required: false,
        doc: "Parent has_many relationship used as the dynamic branch row source"
      ],
      needs: [
        type: :atom,
        required: false,
        doc: "Relationship on dynamic branch rows listing prerequisite rows"
      ]
    ]
  end

  def args, do: [:name, {:optional, :resource}]

  def target, do: __MODULE__

  @doc "Returns true when the branch is sourced from a parent relationship."
  @spec dynamic?(branch :: t()) :: boolean()
  def dynamic?(%__MODULE__{relationship: relationship})
      when is_atom(relationship) and not is_nil(relationship),
      do: true

  def dynamic?(%__MODULE__{resource: nil}), do: true
  def dynamic?(%__MODULE__{}), do: false

  @doc "Returns the authored relationship name for a dynamic branch."
  @spec relationship_name(branch :: t()) :: atom()
  def relationship_name(%__MODULE__{relationship: relationship})
      when is_atom(relationship) and not is_nil(relationship),
      do: relationship

  def relationship_name(%__MODULE__{name: name}), do: name
end
