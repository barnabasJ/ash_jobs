defmodule AshJobs.TestRepo do
  @moduledoc false

  use AshPostgres.Repo, otp_app: :ash_jobs

  def on_transaction_begin(_data) do
    :ok
  end

  def installed_extensions do
    # `ash-functions` installs `ash_raise_error`, which AshPostgres needs to
    # express `error(...)` in atomic updates — required for state-machine
    # transitions (e.g. the generated parallel-completion actions) to run
    # atomically under an AshOban trigger.
    ["ash-functions", "uuid-ossp", "citext"]
  end

  def min_pg_version do
    %Version{major: 13, minor: 0, patch: 0}
  end
end
