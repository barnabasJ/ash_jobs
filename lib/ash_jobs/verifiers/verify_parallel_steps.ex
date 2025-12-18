defmodule AshJobs.Verifiers.VerifyParallelSteps do
  @moduledoc """
  Validates parallel_step configuration in workflows.

  This verifier ensures that parallel_steps are correctly configured:
  - Branch names are unique within each parallel_step
  - on_complete targets a valid step or terminal state
  - on_error (if specified) targets a valid step or terminal state
  - completion_strategy is valid

  ## Validation Rules

  1. **Branch Uniqueness**: Each branch within a parallel_step must have a unique name
  2. **Target Validation**: on_complete and on_error must reference existing steps or terminal states
  3. **Completion Strategy**: Must be :all, :any, or {:require_n, count} where count is positive
  4. **Branch Count**: If using {:require_n, count}, count must be <= number of branches
  """

  use Spark.Dsl.Verifier

  @terminal_states [:completed, :failed, :cancelled]

  def verify(dsl_state) do
    workflow_entities = Spark.Dsl.Extension.get_entities(dsl_state, [:workflow])
    parallel_steps = Enum.filter(workflow_entities, &is_parallel_step?/1)

    if Enum.any?(parallel_steps) do
      all_step_names =
        workflow_entities
        |> Enum.map(& &1.name)
        |> MapSet.new()

      valid_targets = MapSet.union(all_step_names, MapSet.new(@terminal_states))

      with :ok <- validate_branch_uniqueness(parallel_steps),
           :ok <- validate_target_references(parallel_steps, valid_targets),
           :ok <- validate_completion_strategies(parallel_steps) do
        :ok
      end
    else
      :ok
    end
  end

  defp is_parallel_step?(entity) do
    match?(%AshJobs.Dsl.Entities.ParallelStep{}, entity)
  end

  defp validate_branch_uniqueness(parallel_steps) do
    duplicates =
      parallel_steps
      |> Enum.flat_map(fn ps ->
        branch_names = Enum.map(ps.branches, & &1.name)
        unique_names = Enum.uniq(branch_names)

        if length(branch_names) != length(unique_names) do
          duplicate_names =
            branch_names
            |> Enum.frequencies()
            |> Enum.filter(fn {_, count} -> count > 1 end)
            |> Enum.map(fn {name, _} -> name end)

          [{ps.name, duplicate_names}]
        else
          []
        end
      end)

    if Enum.empty?(duplicates) do
      :ok
    else
      messages =
        Enum.map(duplicates, fn {ps_name, dup_names} ->
          "parallel_step :#{ps_name} has duplicate branch names: #{inspect(dup_names)}"
        end)

      {:error,
       Spark.Error.DslError.exception(
         module: __MODULE__,
         message: """
         Duplicate branch names found in parallel_steps:

         #{Enum.join(messages, "\n")}

         Each branch within a parallel_step must have a unique name.
         """
       )}
    end
  end

  defp validate_target_references(parallel_steps, valid_targets) do
    invalid_refs =
      parallel_steps
      |> Enum.flat_map(fn ps ->
        targets =
          [ps.on_complete, ps.on_error]
          |> Enum.reject(&is_nil/1)

        targets
        |> Enum.reject(&MapSet.member?(valid_targets, &1))
        |> Enum.map(fn invalid ->
          routing_type =
            cond do
              ps.on_complete == invalid -> "on_complete"
              ps.on_error == invalid -> "on_error"
              true -> "unknown"
            end

          {ps.name, invalid, routing_type}
        end)
      end)

    if Enum.empty?(invalid_refs) do
      :ok
    else
      messages =
        Enum.map(invalid_refs, fn {ps_name, invalid_target, routing_type} ->
          "parallel_step :#{ps_name} has invalid #{routing_type} reference: :#{invalid_target}"
        end)

      {:error,
       Spark.Error.DslError.exception(
         module: __MODULE__,
         message: """
         Invalid target references in parallel_steps:

         #{Enum.join(messages, "\n")}

         Valid targets are:
         - Step names (including parallel_steps)
         - Terminal states: #{inspect(@terminal_states)}
         """
       )}
    end
  end

  defp validate_completion_strategies(parallel_steps) do
    invalid_strategies =
      parallel_steps
      |> Enum.filter(fn ps ->
        case ps.completion_strategy do
          :all -> false
          :any -> false
          {:require_n, n} when is_integer(n) and n > 0 -> n > length(ps.branches)
          _ -> true
        end
      end)
      |> Enum.map(fn ps ->
        case ps.completion_strategy do
          {:require_n, n} when n > length(ps.branches) ->
            {ps.name, ps.completion_strategy,
             "require_n count (#{n}) exceeds branch count (#{length(ps.branches)})"}

          strategy ->
            {ps.name, strategy, "invalid strategy"}
        end
      end)

    if Enum.empty?(invalid_strategies) do
      :ok
    else
      messages =
        Enum.map(invalid_strategies, fn {ps_name, strategy, reason} ->
          "parallel_step :#{ps_name} - #{reason}: #{inspect(strategy)}"
        end)

      {:error,
       Spark.Error.DslError.exception(
         module: __MODULE__,
         message: """
         Invalid completion strategies in parallel_steps:

         #{Enum.join(messages, "\n")}

         Valid completion strategies are:
         - :all - All branches must complete successfully
         - :any - Any branch completing successfully is enough
         - {:require_n, count} - At least count branches must succeed (count must be <= branch count)
         """
       )}
    end
  end
end
