defmodule AshJobs.TestRepo do
  @moduledoc false

  use AshPostgres.Repo,
    otp_app: :ash_jobs,
    warn_on_missing_ash_functions?: false

  def on_transaction_begin(_data) do
    :ok
  end

  def installed_extensions do
    ["uuid-ossp", "citext"]
  end

  def min_pg_version do
    %Version{major: 13, minor: 0, patch: 0}
  end
end
