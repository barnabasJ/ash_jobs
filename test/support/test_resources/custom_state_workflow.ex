defmodule AshJobs.TestResources.CustomStateWorkflow do
  @moduledoc """
  Workflow with custom state attribute name for configuration testing.

  Uses :status instead of the default :state attribute.
  """

  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "custom_state_workflows"
    repo(AshJobs.TestRepo)
  end

  workflow do
    state_attribute :status

    step :initialize do
      action :setup
      on_success(:process)
      queue :default
    end

    step :process do
      action :do_work
      on_success(:completed)
      queue :default
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :result, :string, public?: true

    # Custom state attribute name
    attribute :status, :atom do
      default :initialize
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

    update :setup do
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
        Ash.Changeset.change_attribute(changeset, :result, "custom_done")
      end
    end
  end

  code_interface do
    define :create
    define :setup
    define :do_work
  end
end
