defmodule AshJobs.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_jobs,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.setup": :test,
        "test.reset": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Core Ash framework
      {:ash, "~> 3.9"},
      {:spark, "~> 2.3"},
      {:ash_state_machine, path: "../ash_state_machine", override: true},
      {:ash_oban, "~> 0.7"},
      {:oban, "~> 2.20"},

      # Development & Testing
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sourceror, "~> 1.7", only: [:dev, :test]},
      {:mimic, "~> 1.11", only: :test},
      {:stream_data, "~> 1.2"},

      # Documentation conformance — story<->test traceability gate (shared
      # engine, sibling path dep; resolves in the parent checkout, not in a
      # standalone ash_jobs CI). See
      # documentation/user/qa-engineer/doc-conformance/.
      {:story_traceability, path: "../story_traceability", only: :test},

      # Integration Testing (database layer for tests)
      {:ash_postgres, "~> 2.4", only: :test}
    ]
  end

  defp aliases do
    [
      # Test database setup and management
      "test.setup": [
        "ecto.create -r AshJobs.TestRepo",
        "ecto.migrate -r AshJobs.TestRepo --migrations-path priv/test_repo/migrations"
      ],
      "test.reset": ["ecto.drop -r AshJobs.TestRepo", "test.setup"]
    ]
  end
end
