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

  @type t :: %__MODULE__{
          name: atom(),
          action: atom(),
          on_success: atom(),
          on_error: atom() | nil,
          on_complete: atom() | nil,
          queue: atom(),
          trigger: boolean(),
          timeout_seconds: integer() | nil,
          retry_attempts: integer() | nil,
          retry_delay_seconds: integer() | nil
        }

  defstruct [
    :name,
    :action,
    :on_success,
    :on_error,
    :on_complete,
    :__spark_metadata__,
    queue: :default,
    trigger: true,
    timeout_seconds: nil,
    retry_attempts: nil,
    retry_delay_seconds: nil
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
      ]
    ]
  end

  def args, do: [:name]

  def target, do: __MODULE__
end
