defmodule AshJobs.Transformers.IntegrateOban do
  @moduledoc """
  Transformer that integrates workflow DSL with ash_oban.

  This transformer generates Oban triggers for workflow steps, enabling
  automatic job scheduling based on state transitions.

  **Status**: Stub - Full implementation in Task 8
  """

  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    # Stub implementation - will be completed in Task 8
    {:ok, dsl_state}
  end
end
