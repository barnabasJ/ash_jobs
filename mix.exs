defmodule AshJobs.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_jobs,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

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
      {:ash, "~> 3.7"},
      {:spark, "~> 2.3"},
      {:ash_state_machine, "~> 0.2"},
      {:ash_oban, "~> 0.4"},
      {:oban, "~> 2.20"},

      # Development & Testing
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sourceror, "~> 1.7", only: [:dev, :test]},
      {:mimic, "~> 1.11", only: :test},
      {:stream_data, "~> 1.2"}
    ]
  end
end
