defmodule AshJobs.Errors.CycleDetected do
  @moduledoc "Raised when a needs graph contains a cycle."

  defexception [:cycle]

  @type t :: %__MODULE__{cycle: [term()]}

  @impl Exception
  def message(%__MODULE__{cycle: cycle}) do
    "Cycle detected in needs graph: #{Enum.map_join(cycle, " -> ", &inspect/1)}"
  end
end
