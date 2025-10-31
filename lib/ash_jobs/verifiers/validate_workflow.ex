defmodule AshJobs.Verifiers.ValidateWorkflow do
  @moduledoc """
  Validates workflow structure after transformers have run.

  This verifier performs comprehensive validation of workflow structure:
  - Step references (on_success, on_error, on_complete)
  - Circular dependency detection
  - Action existence
  - Entry point detection
  - Reachability analysis

  ## Validation Rules

  1. **Step References**: All on_success/on_error/on_complete must reference existing steps or terminal states
  2. **Circular Dependencies**: No cycles in step routing
  3. **Action Existence**: All step actions must be defined by user
  4. **Entry Point**: At least one step with no incoming on_success
  5. **Reachability**: All steps must be reachable from entry point

  ## Terminal States

  - :completed - Successful workflow completion
  - :failed - Workflow failed (error state)
  - :cancelled - Workflow cancelled by user
  """

  use Spark.Dsl.Verifier

  @terminal_states [:completed, :failed, :cancelled]

  def verify(dsl_state) do
    workflow = Spark.Dsl.Extension.get_entities(dsl_state, [:workflow])
    steps = workflow

    if Enum.any?(steps) do
      workflow_config =
        Spark.Dsl.Extension.get_opt(dsl_state, [:workflow], :state_attribute, :state)

      workflow_struct = %{
        steps: steps,
        state_attribute: workflow_config
      }

      with :ok <- validate_step_references(workflow_struct),
           :ok <- validate_circular_dependencies(workflow_struct),
           :ok <- validate_actions_exist(dsl_state, workflow_struct),
           :ok <- validate_entry_point(workflow_struct),
           :ok <- validate_reachability(workflow_struct) do
        :ok
      end
    else
      :ok
    end
  end

  # Validation Functions

  defp validate_step_references(workflow) do
    all_steps = MapSet.new(Enum.map(workflow.steps, & &1.name))
    valid_targets = MapSet.union(all_steps, MapSet.new(@terminal_states))

    invalid_refs =
      workflow.steps
      |> Enum.flat_map(fn step ->
        targets =
          [step.on_success, step.on_error, step.on_complete]
          |> Enum.reject(&is_nil/1)

        targets
        |> Enum.reject(&MapSet.member?(valid_targets, &1))
        |> Enum.map(fn invalid ->
          {step.name, invalid, get_routing_type(step, invalid)}
        end)
      end)

    if Enum.empty?(invalid_refs) do
      :ok
    else
      messages =
        Enum.map(invalid_refs, fn {step_name, invalid_target, routing_type} ->
          "Step :#{step_name} has invalid #{routing_type} reference: :#{invalid_target}"
        end)

      {:error,
       Spark.Error.DslError.exception(
         module: __MODULE__,
         message: """
         Invalid step references found:

         #{Enum.join(messages, "\n")}

         Valid targets are:
         - Step names: #{inspect(MapSet.to_list(all_steps))}
         - Terminal states: #{inspect(@terminal_states)}
         """
       )}
    end
  end

  defp get_routing_type(step, target) do
    cond do
      step.on_success == target -> "on_success"
      step.on_error == target -> "on_error"
      step.on_complete == target -> "on_complete"
      true -> "unknown"
    end
  end

  defp validate_circular_dependencies(workflow) do
    # Build directed graph of step dependencies
    graph = build_dependency_graph(workflow)

    # Use depth-first search to detect cycles
    case find_cycle(graph) do
      nil ->
        :ok

      cycle ->
        {:error,
         Spark.Error.DslError.exception(
           module: __MODULE__,
           message: """
           Circular dependency detected in workflow:

           #{format_cycle(cycle)}

           Workflows must be acyclic - each step should eventually lead to a terminal state.
           """
         )}
    end
  end

  defp build_dependency_graph(workflow) do
    workflow.steps
    |> Enum.reduce(%{}, fn step, graph ->
      successors =
        [step.on_success, step.on_error, step.on_complete]
        |> Enum.reject(&is_nil/1)
        |> Enum.reject(&(&1 in @terminal_states))

      Map.put(graph, step.name, successors)
    end)
  end

  defp find_cycle(graph) do
    # DFS cycle detection using three colors:
    # - white (unvisited)
    # - gray (visiting - on current path)
    # - black (visited - finished)

    all_nodes = Map.keys(graph)
    state = %{white: MapSet.new(all_nodes), gray: MapSet.new(), black: MapSet.new()}

    case find_cycle_dfs(all_nodes, graph, state, []) do
      {:cycle, cycle} -> cycle
      _other -> nil
    end
  end

  defp find_cycle_dfs([], _graph, _state, _path), do: nil

  defp find_cycle_dfs([node | rest], graph, state, path) do
    cond do
      MapSet.member?(state.black, node) ->
        # Already fully explored
        find_cycle_dfs(rest, graph, state, path)

      MapSet.member?(state.white, node) ->
        # Start exploring this node
        new_state = %{
          state
          | white: MapSet.delete(state.white, node),
            gray: MapSet.put(state.gray, node)
        }

        new_path = [node | path]

        # Explore neighbors
        neighbors = Map.get(graph, node, [])

        case explore_neighbors(neighbors, graph, new_state, new_path) do
          {:cycle, cycle} ->
            {:cycle, cycle}

          {:ok, final_state} ->
            # Finished exploring this node
            final_state = %{
              final_state
              | gray: MapSet.delete(final_state.gray, node),
                black: MapSet.put(final_state.black, node)
            }

            find_cycle_dfs(rest, graph, final_state, path)
        end

      true ->
        # Node is gray - found cycle!
        cycle_start_index = Enum.find_index(path, &(&1 == node))
        cycle = Enum.take(path, cycle_start_index + 1) |> Enum.reverse()
        cycle
    end
  end

  defp explore_neighbors([], _graph, state, _path), do: {:ok, state}

  defp explore_neighbors([neighbor | rest], graph, state, path) do
    cond do
      MapSet.member?(state.gray, neighbor) ->
        # Found back edge - cycle!
        cycle_start_index = Enum.find_index(path, &(&1 == neighbor))
        cycle = Enum.take(path, cycle_start_index + 1) |> Enum.reverse()
        {:cycle, cycle}

      MapSet.member?(state.black, neighbor) ->
        # Already explored
        explore_neighbors(rest, graph, state, path)

      true ->
        # Need to explore this neighbor
        case find_cycle_dfs([neighbor], graph, state, path) do
          {:cycle, cycle} -> {:cycle, cycle}
          nil -> explore_neighbors(rest, graph, state, path)
          _other -> explore_neighbors(rest, graph, state, path)
        end
    end
  end

  defp format_cycle(cycle) do
    cycle
    |> Enum.map(&":#{&1}")
    |> Enum.join(" -> ")
    |> Kernel.<>(" -> :#{List.first(cycle)}")
  end

  defp validate_actions_exist(dsl_state, workflow) do
    existing_actions = Ash.Resource.Info.actions(dsl_state)
    existing_action_names = MapSet.new(existing_actions, & &1.name)

    missing_actions =
      workflow.steps
      |> Enum.reject(fn step ->
        MapSet.member?(existing_action_names, step.action)
      end)
      |> Enum.map(& &1.action)
      |> Enum.uniq()

    if Enum.empty?(missing_actions) do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         module: __MODULE__,
         message: """
         Missing required actions: #{inspect(missing_actions)}

         All workflow steps must call actions defined in your resource.
         Please define these actions:

         actions do
           #{Enum.map_join(missing_actions, "\n  ", fn action -> "update :#{action} do\n    # Your business logic here\n  end" end)}
         end
         """
       )}
    end
  end

  defp validate_entry_point(workflow) do
    # Find steps with no incoming references
    all_successors =
      workflow.steps
      |> Enum.flat_map(fn step -> [step.on_success, step.on_error, step.on_complete] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 in @terminal_states))
      |> MapSet.new()

    entry_points =
      workflow.steps
      |> Enum.reject(fn step -> MapSet.member?(all_successors, step.name) end)

    if Enum.empty?(entry_points) do
      {:error,
       Spark.Error.DslError.exception(
         module: __MODULE__,
         message: """
         No entry point found in workflow.

         At least one step must have no incoming on_success/on_error/on_complete references.
         This step will be the starting point of the workflow.

         Current steps: #{inspect(Enum.map(workflow.steps, & &1.name))}
         All steps have incoming references - this creates a circular dependency with no entry point.
         """
       )}
    else
      :ok
    end
  end

  defp validate_reachability(workflow) do
    # Find entry points
    all_successors =
      workflow.steps
      |> Enum.flat_map(fn step -> [step.on_success, step.on_error, step.on_complete] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 in @terminal_states))
      |> MapSet.new()

    entry_points =
      workflow.steps
      |> Enum.reject(fn step -> MapSet.member?(all_successors, step.name) end)
      |> Enum.map(& &1.name)

    # BFS from entry points to find all reachable steps
    graph = build_dependency_graph(workflow)
    reachable = compute_reachable(graph, entry_points)

    all_steps = MapSet.new(Enum.map(workflow.steps, & &1.name))
    unreachable = MapSet.difference(all_steps, reachable)

    if MapSet.size(unreachable) == 0 do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         module: __MODULE__,
         message: """
         Unreachable steps found in workflow: #{inspect(MapSet.to_list(unreachable))}

         All steps must be reachable from an entry point.
         Entry points (steps with no incoming references): #{inspect(entry_points)}

         Check your on_success/on_error/on_complete routing to ensure all steps are connected.
         """
       )}
    end
  end

  defp compute_reachable(graph, entry_points) do
    # BFS to find all reachable nodes from entry points
    bfs(graph, MapSet.new(entry_points), :queue.from_list(entry_points))
  end

  defp bfs(graph, visited, queue) do
    case :queue.out(queue) do
      {:empty, _} ->
        visited

      {{:value, node}, new_queue} ->
        neighbors = Map.get(graph, node, [])
        new_neighbors = Enum.reject(neighbors, &MapSet.member?(visited, &1))

        new_visited = Enum.reduce(new_neighbors, visited, &MapSet.put(&2, &1))
        new_queue = Enum.reduce(new_neighbors, new_queue, &:queue.in(&1, &2))

        bfs(graph, new_visited, new_queue)
    end
  end
end
