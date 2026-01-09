defmodule AshJobs.TestResources.SimpleWorkflow do
  @moduledoc """
  Minimal workflow for documentation examples: Process -> Completed
  """

  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "simple_workflows"
    repo(AshJobs.TestRepo)
  end

  workflow do
    triggers(true)

    step :process do
      action :do_work
      on_success(:completed)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :result, :string, public?: true

    attribute :state, :atom do
      default :process
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

    update :do_work do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :result, "processed")
      end
    end
  end

  code_interface do
    define :create
    define :do_work
    define :get_by_id, action: :read, get_by: [:id]
  end
end
