defmodule AshJobs.Dsl.Entities.ParallelStep do
  @moduledoc """
  Defines a parallel step that coordinates multiple concurrent branches.

  A parallel step activates multiple branch workflows that run concurrently.
  The parent workflow waits for branches to complete based on the completion strategy.

  ## Options

  - `:name` (atom, required) - Unique identifier for this parallel step
  - `:completion_strategy` - How to determine completion: `:all`, `:any`, or `{:require_n, count}`
  - `:on_complete` (atom, required) - Next step when completion criteria are met
  - `:on_error` (atom) - Error handler step when completion strategy fails

  ## Completion Strategies

  - `:all` - All branches must complete successfully (default)
  - `:any` - First successful branch triggers completion
  - `{:require_n, count}` - At least `count` branches must succeed

  ## Examples

      parallel_step :process_parallel do
        completion_strategy :all
        on_complete :finalize
        on_error :handle_parallel_failure

        branch :payment, PaymentWorkflow
        branch :inventory, InventoryWorkflow
      end

  Branch resources must:
  - Use the AshJobs extension
  - Have a `parent_id` attribute for the relationship back to the parent
  - Have terminal states (`:completed`, `:failed`) for completion detection
  """

  alias AshJobs.Dsl.Entities.Branch

  @type t :: %__MODULE__{
          name: atom(),
          completion_strategy: :all | :any | {:require_n, pos_integer()},
          on_complete: atom(),
          on_error: atom() | nil,
          queue: atom(),
          branches: [Branch.t()],
          __spark_metadata__: any()
        }

  defstruct [
    :name,
    :on_complete,
    :on_error,
    :__spark_metadata__,
    completion_strategy: :all,
    queue: :default,
    branches: []
  ]

  def schema do
    [
      name: [
        type: :atom,
        required: true,
        doc: "Unique identifier for this parallel step"
      ],
      completion_strategy: [
        type:
          {:or,
           [
             {:in, [:all, :any]},
             {:tuple, [{:literal, :require_n}, :pos_integer]}
           ]},
        default: :all,
        doc: "Completion strategy: `:all`, `:any`, or `{:require_n, count}`"
      ],
      on_complete: [
        type: :atom,
        required: true,
        doc: "Next step when completion criteria are met"
      ],
      on_error: [
        type: :atom,
        required: false,
        doc: "Error handler step when completion strategy fails"
      ],
      queue: [
        type: :atom,
        default: :default,
        doc: "Oban queue for wrapper action triggers (when workflow has triggers: true)"
      ]
    ]
  end

  def args, do: [:name]

  def target, do: __MODULE__
end
