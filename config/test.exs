import Config

# Configure test repository
config :ash_jobs, AshJobs.TestRepo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "ash_jobs_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: String.to_integer(System.get_env("ASH_JOBS_TEST_POOL_SIZE", "10")),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432"))

config :ash_jobs,
  ecto_repos: [AshJobs.TestRepo]

config :ash, :validate_domain_config_inclusion?, false

# Configure Oban for testing
config :ash_jobs, Oban,
  repo: AshJobs.TestRepo,
  testing: :manual,
  queues: [
    orders: 10,
    inventory: 10,
    shipping: 10,
    default: 10
  ],
  plugins: false

# Print only errors during test
config :logger, level: :error
