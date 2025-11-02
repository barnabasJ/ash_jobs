defmodule AshJobs.TestRepo.Migrations.CreateOrderFulfillmentJobs do
  @moduledoc """
  Creates the order_fulfillment_jobs table for integration testing.
  """

  use Ecto.Migration

  def up do
    create table(:order_fulfillment_jobs, primary_key: false) do
      add(:id, :uuid, primary_key: true, null: false)
      add(:order_id, :text, null: false)
      add(:order_data, :map)
      add(:inventory_valid, :boolean, default: false)
      add(:shipment_id, :text)
      add(:error_message, :text)
      add(:state, :text, null: false, default: "load_order")

      timestamps(type: :utc_datetime_usec)
    end

    create index(:order_fulfillment_jobs, [:state])
    create index(:order_fulfillment_jobs, [:order_id])
  end

  def down do
    drop(table(:order_fulfillment_jobs))
  end
end
