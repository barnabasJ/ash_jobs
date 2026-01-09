defmodule AshJobs.Dsl.Entities.Step do
  @moduledoc """
  Defines a step in a workflow.

  A step represents a single unit of work in a sequential workflow.
  Steps execute in order based on explicit routing via `on_success` and `on_error`.

  ## Options

  - `:name` (atom, required) - Unique identifier for this step
  - `:action` (atom, required) - Action to execute for this step
  - `:on_success` (atom, required) - Next step on success (or terminal state like :completed)
  - `:on_error` (atom) - Error handler step on failure
  - `:on_complete` (atom) - Terminal state (alternative to on_success for error handlers)
  - `:queue` (atom) - Oban queue name (defaults to :default)
  - `:trigger` (boolean) - Whether to create Oban trigger (defaults to true, set false for manual steps)
  - `:where` (Ash expression) - Additional filter expression combined with state filter using `and`
  - `:timeout_seconds` (integer) - Step timeout in seconds
  - `:retry_attempts` (integer) - Number of retry attempts on failure
  - `:retry_delay_seconds` (integer) - Delay between retries in seconds

  ## Examples

      step :load_order do
        action :load_full_order
        on_success :validate_inventory
        on_error :handle_load_error
        queue :order_processing
        timeout_seconds 30
      end

      # Step with additional where filter
      step :process_priority_orders do
        action :process_order
        on_success :completed
        where expr(priority == :high and inserted_at < ago(1, :hour))
      end

      # Manual pause point (no automatic Oban trigger)
      step :await_user_confirmation do
        action :send_confirmation_request
        trigger false
        on_success :charge_payment
      end

      # Error handler step
      step :handle_load_error do
        action :send_error_notification
        on_complete :failed  # Terminal state
      end
  """

  @type change_spec :: module() | {module(), keyword()}
  @type validation_spec :: module() | {module(), keyword()}

  @type t :: %__MODULE__{
          name: atom(),
          action: atom(),
          on_success: atom(),
          on_error: atom() | nil,
          on_complete: atom() | nil,
          queue: atom(),
          trigger: boolean(),
          where: Ash.Expr.t() | nil,
          timeout_seconds: integer() | nil,
          retry_attempts: integer() | nil,
          retry_delay_seconds: integer() | nil,
          on_enter: [change_spec()],
          on_enter_validate: [validation_spec()],
          on_exit: [change_spec()],
          on_exit_validate: [validation_spec()]
        }

  defstruct [
    :name,
    :action,
    :on_success,
    :on_error,
    :on_complete,
    :where,
    :__spark_metadata__,
    queue: :default,
    trigger: true,
    timeout_seconds: nil,
    retry_attempts: nil,
    retry_delay_seconds: nil,
    on_enter: [],
    on_enter_validate: [],
    on_exit: [],
    on_exit_validate: []
  ]

  def schema do
    [
      name: [
        type: :atom,
        required: true,
        doc: "Unique identifier for this step"
      ],
      action: [
        type: :atom,
        required: true,
        doc: "Action to execute for this step"
      ],
      on_success: [
        type: :atom,
        required: false,
        doc: "Next step on success (or terminal state like :completed)"
      ],
      on_error: [
        type: :atom,
        required: false,
        doc: "Error handler step on failure"
      ],
      on_complete: [
        type: :atom,
        required: false,
        doc: "Terminal state (alternative to on_success for error handlers)"
      ],
      queue: [
        type: :atom,
        required: false,
        default: :default,
        doc: "Oban queue name"
      ],
      trigger: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Whether to create Oban trigger (set false for manual steps)"
      ],
      where: [
        type: :any,
        required: false,
        doc:
          "Additional filter expression combined with the state filter using `and`. Use `expr(...)` syntax."
      ],
      timeout_seconds: [
        type: :pos_integer,
        required: false,
        doc: "Step timeout in seconds"
      ],
      retry_attempts: [
        type: :pos_integer,
        required: false,
        doc: "Number of retry attempts on failure"
      ],
      retry_delay_seconds: [
        type: :pos_integer,
        required: false,
        doc: "Delay between retries in seconds"
      ],
      on_enter: [
        type: {:list, {:or, [:atom, {:tuple, [:atom, :keyword_list]}]}},
        required: false,
        default: [],
        doc: """
        Changes to run when entering this step's state.

        Supports:
        - Module: `MyApp.Changes.DoSomething`
        - Module with opts: `{MyApp.Changes.DoSomething, opt: value}`

        Entry changes run for ANY transition into this state.
        """
      ],
      on_enter_validate: [
        type: {:list, {:or, [:atom, {:tuple, [:atom, :keyword_list]}]}},
        required: false,
        default: [],
        doc: """
        Validations to run when entering this step's state.

        Entry validations run after entry changes and can rollback the transaction.
        """
      ],
      on_exit: [
        type: {:list, {:or, [:atom, {:tuple, [:atom, :keyword_list]}]}},
        required: false,
        default: [],
        doc: """
        Changes to run when exiting this step's state.

        Exit changes run for ANY transition out of this state.
        """
      ],
      on_exit_validate: [
        type: {:list, {:or, [:atom, {:tuple, [:atom, :keyword_list]}]}},
        required: false,
        default: [],
        doc: """
        Validations to run when exiting this step's state.

        Exit validations run before exit changes and can block the transition.
        """
      ]
    ]
  end

  def args, do: [:name]

  def target, do: __MODULE__
end
