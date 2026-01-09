defmodule AshJobs.TestResources.BranchingWorkflow do
  @moduledoc """
  Workflow with multiple error paths for error handling tests.

  Workflow structure:
  - start -> step_one (success) -> step_two (success) -> completed
  - start -> handle_start_error -> failed
  - step_one -> handle_step_one_error -> failed
  - step_two -> handle_step_two_error -> failed
  """

  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "branching_workflows"
    repo(AshJobs.TestRepo)
  end

  workflow do
    triggers(true)

    step :start do
      action :initialize
      on_success(:step_one)
      on_error :handle_start_error
      queue :default
      retry_attempts(1)
    end

    step :step_one do
      action :process_one
      on_success(:step_two)
      on_error :handle_step_one_error
      queue :default
      retry_attempts(1)
    end

    step :step_two do
      action :process_two
      on_success(:completed)
      on_error :handle_step_two_error
      queue :default
      retry_attempts(1)
    end

    step :handle_start_error do
      action :notify_start_error
      on_complete(:failed)
    end

    step :handle_step_one_error do
      action :notify_step_one_error
      on_complete(:failed)
    end

    step :handle_step_two_error do
      action :notify_step_two_error
      on_complete(:failed)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :step_one_data, :string, public?: true
    attribute :step_two_data, :string, public?: true
    attribute :error_message, :string, public?: true
    attribute :force_error_at, :string, public?: true

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
      accept [:name, :force_error_at]
    end

    update :initialize do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        record = changeset.data

        if record.force_error_at == "start" do
          Ash.Changeset.add_error(changeset, "Forced error at start")
        else
          changeset
        end
      end
    end

    update :process_one do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        record = changeset.data

        if record.force_error_at == "step_one" do
          Ash.Changeset.add_error(changeset, "Forced error at step_one")
        else
          Ash.Changeset.change_attribute(changeset, :step_one_data, "processed")
        end
      end
    end

    update :process_two do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        record = changeset.data

        if record.force_error_at == "step_two" do
          Ash.Changeset.add_error(changeset, "Forced error at step_two")
        else
          Ash.Changeset.change_attribute(changeset, :step_two_data, "completed")
        end
      end
    end

    update :notify_start_error do
      require_atomic? false
      argument :error, :term, allow_nil?: true

      change fn changeset, _context ->
        error_msg =
          Ash.Changeset.get_argument(changeset, :error)
          |> case do
            %{message: msg} -> msg
            msg when is_binary(msg) -> msg
            _ -> "Error at start"
          end

        Ash.Changeset.change_attribute(changeset, :error_message, error_msg)
      end
    end

    update :notify_step_one_error do
      require_atomic? false
      argument :error, :term, allow_nil?: true

      change fn changeset, _context ->
        error_msg =
          Ash.Changeset.get_argument(changeset, :error)
          |> case do
            %{message: msg} -> msg
            msg when is_binary(msg) -> msg
            _ -> "Error at step_one"
          end

        Ash.Changeset.change_attribute(changeset, :error_message, error_msg)
      end
    end

    update :notify_step_two_error do
      require_atomic? false
      argument :error, :term, allow_nil?: true

      change fn changeset, _context ->
        error_msg =
          Ash.Changeset.get_argument(changeset, :error)
          |> case do
            %{message: msg} -> msg
            msg when is_binary(msg) -> msg
            _ -> "Error at step_two"
          end

        Ash.Changeset.change_attribute(changeset, :error_message, error_msg)
      end
    end
  end

  code_interface do
    define :create
    define :initialize
    define :process_one
    define :process_two
    define :notify_start_error
    define :notify_step_one_error
    define :notify_step_two_error
    define :get_by_id, action: :read, get_by: [:id]
  end
end
