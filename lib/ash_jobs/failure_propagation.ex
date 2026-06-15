defmodule AshJobs.FailurePropagation do
  @moduledoc "Propagates terminal skip state through a needs graph."

  @doc "Marks all non-terminal dependents of `record` as skipped, recursively."
  @spec propagate_skip(record :: Ash.Resource.record()) :: :ok | {:error, term()}
  def propagate_skip(record) do
    record
    |> AshJobs.Readiness.dependents()
    |> Enum.reduce_while(:ok, fn dependent, :ok ->
      case skip_record(dependent) do
        {:ok, skipped} ->
          case propagate_skip(skipped) do
            :ok -> {:cont, :ok}
            {:error, error} -> {:halt, {:error, error}}
          end

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  @doc "Marks one record skipped unless it has already reached a terminal state."
  @spec skip_record(record :: Ash.Resource.record()) ::
          {:ok, Ash.Resource.record()} | {:error, term()}
  def skip_record(record) do
    if AshJobs.Readiness.terminal_state?(record) do
      {:ok, record}
    else
      state_attribute = AshJobs.Info.state_attribute(record.__struct__)

      record
      |> Ash.Changeset.for_update(:skip, %{})
      |> Ash.Changeset.force_change_attribute(state_attribute, :skipped)
      |> Ash.update()
    end
  end
end
