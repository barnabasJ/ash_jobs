defmodule AshJobs.CycleDetection do
  @moduledoc "Detects cycles in workflow row dependency graphs."

  alias AshJobs.Errors.CycleDetected

  @type edge :: {term(), term()}
  @type result :: :ok | {:error, CycleDetected.t()}

  @doc "Detects whether directed `edges` contain a cycle over `nodes`."
  @spec detect(nodes :: [term()], edges :: [edge()]) :: result()
  def detect(nodes, edges) do
    graph = build_graph(nodes, edges)
    state = %{visiting: MapSet.new(), visited: MapSet.new()}

    Enum.reduce_while(nodes, state, fn node, state ->
      case visit(node, graph, state, []) do
        {:ok, state} -> {:cont, state}
        {:cycle, cycle} -> {:halt, {:error, %CycleDetected{cycle: cycle}}}
      end
    end)
    |> case do
      %{} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc "Loads a record collection's needs relationship and checks it for cycles."
  @spec detect_records(records :: [Ash.Resource.record()], needs_relationship :: atom()) ::
          result()
  def detect_records(records, needs_relationship) do
    records = Enum.map(records, &Ash.load!(&1, [needs_relationship], lazy?: false))
    ids = Enum.map(records, &Map.fetch!(&1, :id))

    edges =
      Enum.flat_map(records, fn record ->
        record
        |> Map.get(needs_relationship, [])
        |> List.wrap()
        |> Enum.map(&{Map.fetch!(record, :id), Map.fetch!(&1, :id)})
      end)

    detect(ids, edges)
  end

  @doc "Detects a parent's dynamic row cycle and marks the parent failed when one exists."
  @spec detect_records_or_fail_parent(
          parent :: Ash.Resource.record(),
          rows_relationship :: atom(),
          needs_relationship :: atom()
        ) :: {:ok, Ash.Resource.record()} | {:error, term()}
  def detect_records_or_fail_parent(parent, rows_relationship, needs_relationship) do
    parent = Ash.load!(parent, [rows_relationship], lazy?: false)
    records = Map.get(parent, rows_relationship, []) |> List.wrap()

    case detect_records(records, needs_relationship) do
      :ok ->
        {:ok, parent}

      {:error, %CycleDetected{} = error} ->
        fail_parent(parent, error)
    end
  end

  defp build_graph(nodes, edges) do
    graph = Map.new(nodes, &{&1, []})

    Enum.reduce(edges, graph, fn {from, to}, graph ->
      Map.update(graph, from, [to], &[to | &1])
    end)
  end

  defp visit(node, graph, state, path) do
    cond do
      MapSet.member?(state.visited, node) ->
        {:ok, state}

      MapSet.member?(state.visiting, node) ->
        {:cycle, cycle_path(node, path)}

      true ->
        state = %{state | visiting: MapSet.put(state.visiting, node)}

        graph
        |> Map.get(node, [])
        |> Enum.reduce_while({:ok, state}, fn neighbor, {:ok, state} ->
          case visit(neighbor, graph, state, [node | path]) do
            {:ok, state} -> {:cont, {:ok, state}}
            {:cycle, cycle} -> {:halt, {:cycle, cycle}}
          end
        end)
        |> case do
          {:ok, state} ->
            {:ok,
             %{
               state
               | visiting: MapSet.delete(state.visiting, node),
                 visited: MapSet.put(state.visited, node)
             }}

          {:cycle, cycle} ->
            {:cycle, cycle}
        end
    end
  end

  defp cycle_path(node, path) do
    path
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 != node))
    |> Kernel.++([node])
  end

  defp fail_parent(parent, error) do
    state_attribute = AshJobs.Info.state_attribute(parent.__struct__)

    parent
    |> Ash.Changeset.for_update(:fail_cycle, %{})
    |> Ash.Changeset.force_change_attribute(state_attribute, :failed)
    |> maybe_set_error_message(error)
    |> Ash.update()
    |> case do
      {:ok, _parent} -> {:error, error}
      {:error, update_error} -> {:error, update_error}
    end
  end

  defp maybe_set_error_message(changeset, error) do
    if Ash.Resource.Info.attribute(changeset.resource, :error_message) do
      Ash.Changeset.force_change_attribute(changeset, :error_message, Exception.message(error))
    else
      changeset
    end
  end
end
