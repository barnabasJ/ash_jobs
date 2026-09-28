defmodule AshJobs.TestRepo.Migrations.PolicyGatedJobs do
  @moduledoc """
  Creates the table for the `PolicyGatedJob` fixture — the resource whose
  policies allow reads only through the AshOban interaction context.
  """
  use Ecto.Migration

  def up do
    create_if_not_exists table(:policy_gated_jobs, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:name, :text, null: false)
      add(:admitted, :boolean, null: false, default: false)
      add(:run_count, :integer, null: false, default: 0)
      add(:state, :text, null: false, default: "pending")

      timestamps()
    end
  end

  def down do
    drop_if_exists(table(:policy_gated_jobs))
  end
end
