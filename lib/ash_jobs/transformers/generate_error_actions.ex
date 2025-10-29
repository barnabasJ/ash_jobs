defmodule AshJobs.Transformers.GenerateErrorActions do
  @moduledoc """
  Generates error handler actions for workflow steps.

  For each step with an `on_error` option, this transformer generates a simple
  error handler action if one doesn't already exist. Generated error handlers
  simply transition the workflow to the :failed state.

  ## Generated Actions

  Error handler actions are generated with:
  - `argument :error, :map` - Error details from Oban
  - `accept []` - No direct attribute changes
  - `require_atomic? false` - Allow non-atomic updates
  - State transition change to :failed

  ## Example

  Given:
      step :load_order do
        on_error :handle_load_error
      end

  Generates:
      update :handle_load_error do
        argument :error, :map, allow_nil?: false
        accept []
        require_atomic? false
        change {AshStateMachine.Transition, to: :failed}
      end
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
    # Build error handler action
    action = %Ash.Resource.Actions.Update{
      name: action_name,
      type: :update,
      accept: [],
      require_atomic?: false,
      arguments: [
        %Ash.Resource.Actions.Argument{
          name: :error,
          type: :map,
          allow_nil?: false
        }
      ],
      changes: [
        {AshStateMachine.BuiltinChanges.TransitionState, to: :failed}
      ]
    }

    # Add action to DSL state using Spark.Dsl.Transformer
    Spark.Dsl.Transformer.add_entity(dsl_state, [:actions], action)
  end
end
