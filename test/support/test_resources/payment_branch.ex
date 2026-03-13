defmodule AshJobs.TestResources.PaymentBranch do
  @moduledoc """
  Branch resource for payment processing in parallel workflow tests.

  States: pending -> processing -> completed (or failed)
  """

  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "payment_branches"
    repo(AshJobs.TestRepo)
  end

  workflow do
    step :pending do
      action :process_payment
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

    update :process_payment do
      require_atomic? false
      accept []
    end
  end

  code_interface do
    define :create
    define :process_payment
    define :get_by_id, action: :read, get_by: [:id]
  end
end
