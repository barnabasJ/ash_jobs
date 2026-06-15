defmodule AshJobs.TestChanges.MarkDagJobRun do
  @moduledoc false
  use Ash.Resource.Change

  @impl Ash.Resource.Change
  @spec change(changeset :: Ash.Changeset.t(), opts :: keyword(), context :: map()) ::
          Ash.Changeset.t()
  def change(changeset, _opts, _context) do
    now = DateTime.utc_now()
    run_count = (changeset.data.run_count || 0) + 1

    changeset
    |> Ash.Changeset.change_attribute(:run_count, run_count)
    |> Ash.Changeset.change_attribute(:started_at, changeset.data.started_at || now)
    |> Ash.Changeset.change_attribute(:completed_at, now)
  end
end
