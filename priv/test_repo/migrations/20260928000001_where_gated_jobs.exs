defmodule AshJobs.TestRepo.Migrations.WhereGatedJobs do
  @moduledoc """
  Creates tables for the `WhereGatedJob` integration fixtures — the resource
  whose entry step carries a custom `where` gate (`admitted == true`).
  """
  use Ecto.Migration

  def up do
    create_if_not_exists table(:where_gated_jobs, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:name, :text, null: false)
      add(:admitted, :boolean, null: false, default: false)
      add(:run_count, :integer, null: false, default: 0)
      add(:started_at, :utc_datetime_usec)
      add(:completed_at, :utc_datetime_usec)
      add(:state, :text, null: false, default: "pending")

      timestamps()
    end

    create_if_not_exists table(:where_gated_needs, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:dependent_id, :uuid, null: false)
      add(:need_id, :uuid, null: false)
    end

    create_if_not_exists(index(:where_gated_needs, [:dependent_id]))
    create_if_not_exists(index(:where_gated_needs, [:need_id]))
  end

  def down do
    drop_if_exists(table(:where_gated_needs))
    drop_if_exists(table(:where_gated_jobs))
  end
end
