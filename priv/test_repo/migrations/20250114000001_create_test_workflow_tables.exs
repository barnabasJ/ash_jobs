defmodule AshJobs.TestRepo.Migrations.CreateTestWorkflowTables do
  @moduledoc """
  Creates tables for integration test resources.
  """
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

    create_if_not_exists table(:order_fulfillment_jobs, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()"))
      add(:order_id, :text, null: false)
      add(:order_data, :map)
      add(:inventory_valid, :boolean, default: false)
      add(:shipment_id, :text)
      add(:error_message, :text)
      add(:state, :text, null: false, default: "load_order")

      timestamps()
    end

    create_if_not_exists table(:simple_workflows, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()"))
      add(:name, :text, null: false)
      add(:result, :text)
      add(:state, :text, null: false, default: "process")

      timestamps()
    end

    create_if_not_exists table(:branching_workflows, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()"))
      add(:name, :text, null: false)
      add(:step_one_data, :text)
      add(:step_two_data, :text)
      add(:error_message, :text)
      add(:force_error_at, :text)
      add(:state, :text, null: false, default: "start")

      timestamps()
    end

    create_if_not_exists table(:manual_workflows, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()"))
      add(:name, :text, null: false)
      add(:auto_data, :text)
      add(:manual_data, :text)
      add(:state, :text, null: false, default: "auto_step")

      timestamps()
    end

    create_if_not_exists table(:long_running_workflows, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()"))
      add(:name, :text, null: false)
      add(:quick_data, :text)
      add(:slow_data, :text)
      add(:retry_data, :text)
      add(:state, :text, null: false, default: "quick_step")

      timestamps()
    end

    create_if_not_exists table(:single_step_workflows, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()"))
      add(:name, :text, null: false)
      add(:result, :text)
      add(:state, :text, null: false, default: "only_step")

      timestamps()
    end

    create_if_not_exists table(:multi_terminal_workflows, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()"))
      add(:name, :text, null: false)
      add(:result, :text)
      add(:error_message, :text)
      add(:cancellation_reason, :text)
      add(:state, :text, null: false, default: "start")

      timestamps()
    end

    create_if_not_exists table(:custom_state_workflows, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("uuid_generate_v4()"))
      add(:name, :text, null: false)
      add(:result, :text)
      add(:status, :text, null: false, default: "initialize")

      timestamps()
    end
  end

  def down do
    drop(table(:order_fulfillment_jobs))
    drop(table(:simple_workflows))
    drop(table(:branching_workflows))
    drop(table(:manual_workflows))
    drop(table(:long_running_workflows))
    drop(table(:single_step_workflows))
    drop(table(:multi_terminal_workflows))
    drop(table(:custom_state_workflows))
  end
end
