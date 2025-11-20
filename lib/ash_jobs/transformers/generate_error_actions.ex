defmodule AshJobs.Transformers.GenerateErrorActions do
  @moduledoc """
  Generates error handler actions for workflow steps.

  For each step with an `on_error` option, this transformer generates a minimal
  error handler action if one doesn't already exist.

  ## Generated Actions

  Error handler actions are generated with:
  - `argument :error, :term` - Error details from Oban (allow_nil: true for compatibility)
  - `accept []` - No direct attribute changes
  - `require_atomic? false` - Allow non-atomic updates
  - No changes - AshJobs.Change module handles state transitions via on_complete

  ## Example

  Given:
      step :load_order do
        on_error :handle_load_error
      end

      step :handle_load_error do
        action :handle_load_error
        on_complete :failed
      end

  Generates:
      update :handle_load_error do
        argument :error, :term, allow_nil?: true
        accept []
        require_atomic? false
      end

  The AshJobs.Change module (injected by BuildWorkflow) handles the state
  transition to :failed via the step's on_complete option.
  """

  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    # Get workflow steps from DSL
    steps = Spark.Dsl.Extension.get_entities(dsl_state, [:workflow])

    if steps && length(steps) > 0 do
      # Find all error handler steps that need actions
      error_steps = find_error_steps(steps)

      # Generate actions for steps that don't already have them
      dsl_state = generate_missing_error_actions(dsl_state, error_steps)

      {:ok, dsl_state}
    else
      # No workflow defined, skip
      {:ok, dsl_state}
    end
  end

  defp find_error_steps(steps) do
    steps
    |> Enum.map(& &1.on_error)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp generate_missing_error_actions(dsl_state, error_steps) do
    existing_actions = Ash.Resource.Info.actions(dsl_state)
    existing_action_names = MapSet.new(existing_actions, & &1.name)

    error_steps
    |> Enum.reject(&MapSet.member?(existing_action_names, &1))
    |> Enum.reduce(dsl_state, fn error_step_name, acc_state ->
      add_error_action(acc_state, error_step_name)
    end)
  end

  defp add_error_action(dsl_state, action_name) do
    # Build error handler action using Spark entity builders
    # Note: State transitions are handled by AshJobs.Change module
    # which routes to terminal states via on_complete

    # First, build the error argument entity
    with {:ok, error_argument} <-
           Ash.Resource.Builder.build_action_argument(
             :error,
             :term,
             allow_nil?: true
           ),
         # Then build the update action entity with the argument
         {:ok, action} <-
           Ash.Resource.Builder.build_action(
             :update,
             action_name,
             accept: [],
             require_atomic?: false,
             arguments: [error_argument]
           ) do
      # Add action to DSL state using Spark.Dsl.Transformer
      Spark.Dsl.Transformer.add_entity(dsl_state, [:actions], action)
    else
      {:error, error} ->
        raise "Failed to build error handler action #{action_name}: #{inspect(error)}"
    end
  end
end
