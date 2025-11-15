defmodule AshJobs.TestResources.MultiTerminalWorkflow do
  @moduledoc """
  Edge case: Workflow with multiple terminal states.

  Tests that workflows can end in different states:
  - completed (success path)
  - cancelled (user cancellation)
  - failed (error path)
  """

  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "multi_terminal_workflows"
    repo(AshJobs.TestRepo)
  end

  workflow do
    step :start do
      action :begin
      on_success(:process)
      on_error :handle_error
    end

    step :process do
      action :do_work
      on_success(:completed)
      on_error :handle_error
    end

    step :handle_error do
      action :notify_error
      on_complete(:failed)
    end

    step :cancel do
      action :do_cancel
      on_complete(:cancelled)
      trigger false
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :result, :string, public?: true
    attribute :error_message, :string, public?: true
    attribute :cancellation_reason, :string, public?: true

    attribute :state, :atom do
      default :start
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name]
    end

    update :begin do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        changeset
      end
    end

    update :do_work do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :result, "work_done")
      end
    end

    update :notify_error do
      require_atomic? false
      argument :error, :map, allow_nil?: true

      change fn changeset, _context ->
        error_msg =
          Ash.Changeset.get_argument(changeset, :error)
          |> case do
            %{message: msg} -> msg
            msg when is_binary(msg) -> msg
            _ -> "Unknown error"
          end

        Ash.Changeset.change_attribute(changeset, :error_message, error_msg)
      end
    end

    update :do_cancel do
      require_atomic? false
      accept [:cancellation_reason]

      change fn changeset, _context ->
        reason = Ash.Changeset.get_attribute(changeset, :cancellation_reason) || "User cancelled"
        Ash.Changeset.change_attribute(changeset, :cancellation_reason, reason)
      end
    end
  end

  code_interface do
    define :create
    define :begin
    define :do_work
    define :notify_error
    define :do_cancel
    define :get_by_id, action: :read, get_by: [:id]
  end
end
