defmodule AshJobs.TestResources.InventoryBranch do
  @moduledoc """
  Branch resource for inventory reservation in parallel workflow tests.

  States: pending -> reserving -> reserved (or unavailable)
  """

  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "inventory_branches"
    repo(AshJobs.TestRepo)
  end

  workflow do
    step :pending do
      action :reserve_inventory
      on_success(:reserving)
    end

    step :reserving do
      action :confirm_inventory
      on_success(:completed)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :parent_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :state, :atom do
      default :pending
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]

    create :create do
      accept [:parent_id]
    end

    update :reserve_inventory do
      require_atomic? false
      accept []
    end

    update :confirm_inventory do
      require_atomic? false
      accept []
    end
  end

  code_interface do
    define :create
    define :reserve_inventory
    define :confirm_inventory
    define :get_by_id, action: :read, get_by: [:id]
  end
end
