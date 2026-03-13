defmodule AshJobs.TestResources.ParallelWorkflow do
  @moduledoc """
  Parent workflow with parallel step for integration testing.

  Workflow structure:
  - start -> process_parallel (parallel: payment + inventory) -> finalize -> completed
  """

  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "parallel_workflows"
    repo(AshJobs.TestRepo)
  end

  workflow do
    triggers(true)

    step :start do
      action :initialize
      on_success(:process_parallel)
    end

    parallel_step :process_parallel do
      completion_strategy(:all)
      on_complete(:finalize)

      branch(:payment, AshJobs.TestResources.PaymentBranch)
      branch(:inventory, AshJobs.TestResources.InventoryBranch)
    end

    step :finalize do
      action :finalize_order
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

    update :initialize do
      require_atomic? false
      accept []
    end

    update :finalize_order do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :result, "finalized")
      end
    end
  end

  code_interface do
    define :create
    define :initialize
    define :finalize_order
    define :get_by_id, action: :read, get_by: [:id]
  end
end
