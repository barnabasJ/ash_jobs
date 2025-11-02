defmodule AshJobs.TestResources.OrderFulfillmentJob do
  @moduledoc """
  Real workflow resource for integration testing.

  Simulates an order fulfillment workflow with multiple steps:
  1. Load order data
  2. Validate inventory
  3. Create shipment
  4. Complete
  """

  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "order_fulfillment_jobs"
    repo(AshJobs.TestRepo)
  end

  workflow do
    step :load_order do
      action :load_order_data
      on_success(:validate_inventory)
      on_error :handle_load_error
      queue :orders
    end

    step :validate_inventory do
      action :check_inventory
      on_success(:create_shipment)
      on_error :handle_inventory_error
      queue :inventory
    end

    step :create_shipment do
      action :generate_shipment
      on_success(:completed)
      queue :shipping
    end

    step :handle_load_error do
      action :notify_load_error
      on_complete(:failed)
    end

    step :handle_inventory_error do
      action :notify_inventory_error
      on_complete(:failed)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :order_id, :string do
      allow_nil? false
      public? true
    end

    attribute :order_data, :map do
      public? true
    end

    attribute :inventory_valid, :boolean, default: false, public?: true
    attribute :shipment_id, :string, public?: true
    attribute :error_message, :string, public?: true

    # State attribute managed by ash_state_machine
    attribute :state, :atom do
      default :load_order
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]

    create :create do
      accept [:order_id]

      change fn changeset, _ ->
        Ash.Changeset.force_change_attribute(changeset, :state, :load_order)
      end
    end

    # Generic update action for testing (state changes must go through workflow actions)
    update :update do
      require_atomic? false
      accept [:order_data, :inventory_valid, :shipment_id, :error_message]
    end

    # Workflow step actions

    update :load_order_data do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        # Simulate loading order data
        order_data = %{
          items: [%{sku: "ABC123", quantity: 2}],
          customer: "test@example.com",
          loaded_at: DateTime.utc_now()
        }

        Ash.Changeset.change_attribute(changeset, :order_data, order_data)
        # State transition handled automatically by AshJobs.Change
      end
    end

    update :check_inventory do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        # Simulate inventory check
        Ash.Changeset.change_attribute(changeset, :inventory_valid, true)
        # State transition handled automatically by AshJobs.Change
      end
    end

    update :generate_shipment do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        # Simulate shipment creation
        shipment_id = "SHIP-#{:rand.uniform(99999)}"

        Ash.Changeset.change_attribute(changeset, :shipment_id, shipment_id)
        # State transition handled automatically by AshJobs.Change
      end
    end

    update :notify_load_error do
      require_atomic? false
      argument :error, :map, allow_nil?: true

      change fn changeset, _context ->
        error_msg =
          Ash.Changeset.get_argument(changeset, :error)
          |> case do
            %{message: msg} -> msg
            msg when is_binary(msg) -> msg
            _ -> "Unknown error during order loading"
          end

        Ash.Changeset.change_attribute(changeset, :error_message, error_msg)
        # State transition handled automatically by AshJobs.Change
      end
    end

    update :notify_inventory_error do
      require_atomic? false
      argument :error, :map, allow_nil?: true

      change fn changeset, _context ->
        error_msg =
          Ash.Changeset.get_argument(changeset, :error)
          |> case do
            %{message: msg} -> msg
            msg when is_binary(msg) -> msg
            _ -> "Inventory validation failed"
          end

        Ash.Changeset.change_attribute(changeset, :error_message, error_msg)
        # State transition handled automatically by AshJobs.Change
      end
    end
  end

  code_interface do
    define :create
    define :load_order_data
    define :check_inventory
    define :generate_shipment
    define :notify_load_error
    define :notify_inventory_error
  end
end
