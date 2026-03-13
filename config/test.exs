import Config

# Configure test repository
config :ash_jobs, AshJobs.TestRepo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "ash_jobs_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432"))

config :ash_jobs,
  ecto_repos: [AshJobs.TestRepo],
  ash_domains: [AshJobs.TestDomain]

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
