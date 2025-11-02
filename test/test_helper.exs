# Load compilation helpers (not compiled as a module)
Code.require_file("support/compilation_helpers.exs", __DIR__)

# Start the test repo
{:ok, _} = AshJobs.TestRepo.start_link()

# Run migrations
migrations_path = Path.join(__DIR__, "../priv/test_repo/migrations")

Ecto.Migrator.run(
  AshJobs.TestRepo,
  migrations_path,
  :up,
  all: true
)

# Start Oban for testing
{:ok, _} = Oban.start_link(Application.get_env(:ash_jobs, Oban))

# Set up Ecto sandbox for concurrent tests
Ecto.Adapters.SQL.Sandbox.mode(AshJobs.TestRepo, :manual)

ExUnit.start()
