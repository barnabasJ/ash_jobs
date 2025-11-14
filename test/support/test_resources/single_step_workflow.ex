defmodule AshJobs.TestResources.SingleStepWorkflow do
  @moduledoc """
  Edge case: Workflow with only one step that transitions directly to completed.
  """

  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "single_step_workflows"
    repo(AshJobs.TestRepo)
  end

  workflow do
    step :only_step do
      action :process
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
      default :only_step
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

    update :process do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :result, "done")
      end
    end
  end

  code_interface do
    define :create
    define :process
  end
end
