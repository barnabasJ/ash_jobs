# Used by "mix format"
[
  import_deps: [:ash, :ash_state_machine, :ash_oban],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter]
]
