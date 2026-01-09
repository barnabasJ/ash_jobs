defmodule AshJobs.TestResources.ManualWorkflow do
  @moduledoc """
  Workflow with manual steps (trigger: false) for testing non-automatic execution.

  Workflow structure:
  - auto_step (trigger: true) -> manual_step (trigger: false) -> completed
  """

  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "manual_workflows"
    repo(AshJobs.TestRepo)
  end

  workflow do
    triggers(true)

    step :auto_step do
      action :process_auto
      on_success(:manual_step)
      queue :default
    end

    step :manual_step do
      action :process_manual
      on_success(:completed)
      trigger false
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :auto_data, :string, public?: true
    attribute :manual_data, :string, public?: true

    attribute :state, :atom do
      default :auto_step
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

    update :process_auto do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :auto_data, "auto_processed")
      end
    end

    update :process_manual do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :manual_data, "manual_processed")
      end
    end
  end

  code_interface do
    define :create
    define :process_auto
    define :process_manual
    define :get_by_id, action: :read, get_by: [:id]
  end
end
