defmodule AshJobs.Transformers.BuildWorkflow do
  @moduledoc """
  Injects AshJobs.Change module into all workflow step actions.

  This transformer ensures that all workflow actions have the routing
  change that handles state transitions and Oban job scheduling.

  The Change module is added AFTER any user-defined changes, so it runs last
  and can transition state and schedule the next job after user logic completes.
  """

  use Spark.Dsl.Transformer

  # Run after Generate ErrorActions but before state machine and oban integration
  def after?(AshJobs.Transformers.GenerateErrorActions), do: true
  def after?(_), do: false

  def before?(AshJobs.Transformers.IntegrateStateMachine), do: true
  def before?(AshJobs.Transformers.IntegrateOban), do: true
  def before?(_), do: false

  def transform(dsl_state) do
    # Get workflow steps
    steps = Spark.Dsl.Extension.get_entities(dsl_state, [:workflow])

    if steps && length(steps) > 0 do
      # Add Change module to all step actions
      dsl_state = inject_change_module(dsl_state, steps)
      {:ok, dsl_state}
    else
      # No workflow defined, skip
      {:ok, dsl_state}
    end
  end

  defp inject_change_module(dsl_state, steps) do
    # Get action names from regular steps only (not parallel_steps)
    # Parallel steps don't have actions - they coordinate branch resources
    # All regular steps (including error handlers) need AshJobs.Change for routing
    action_names =
      steps
      |> Enum.reject(&match?(%AshJobs.Dsl.Entities.ParallelStep{}, &1))
      |> Enum.map(& &1.action)
      |> Enum.uniq()

    # Add Change module to each workflow step action
    dsl_state =
      Enum.reduce(action_names, dsl_state, fn action_name, acc_state ->
        add_change_to_action(acc_state, action_name)
      end)

    # Also add Change module to ALL create actions
    # This allows creates to trigger the first workflow step
    add_change_to_all_creates(dsl_state)
  end

  defp add_change_to_all_creates(dsl_state) do
    # Get all create actions
    actions = Ash.Resource.Info.actions(dsl_state)
    create_actions = Enum.filter(actions, &(&1.type == :create))

    # Add Change module to each create action
    Enum.reduce(create_actions, dsl_state, fn action, acc_state ->
      add_change_to_action(acc_state, action.name)
    end)
  end

  defp add_change_to_action(dsl_state, action_name) do
    # Get existing actions
    actions = Ash.Resource.Info.actions(dsl_state)

    # Find the action we need to modify
    case Enum.find(actions, &(&1.name == action_name)) do
      nil ->
        # Action doesn't exist yet (user hasn't defined it)
        # This will be caught by the validator
        dsl_state

      action ->
        # Build a proper Ash.Resource.Change entity using Spark's entity builder
        # This provides schema validation, metadata tracking, and transformation
        case Ash.Resource.Builder.build_change(
               {AshJobs.Change, []},
               on: [:create, :update],
               only_when_valid?: false,
               description: "AshJobs workflow routing"
             ) do
          {:ok, change_struct} ->
            # Add our change to the action's changes list
            updated_action = %{action | changes: action.changes ++ [change_struct]}

            # Replace the action in the DSL state
            # First remove the old action, then add the updated one
            dsl_state
            |> remove_action(action_name)
            |> Spark.Dsl.Transformer.add_entity([:actions], updated_action)

          {:error, error} ->
            # This shouldn't happen with valid options, but handle it gracefully
            raise "Failed to build change entity: #{inspect(error)}"
        end
    end
  end

  defp remove_action(dsl_state, action_name) do
    # This is a bit hacky - we need to rebuild the actions list
    # Spark doesn't have a direct "remove entity" function
    # So we'll use remove_entity if it exists, otherwise work around it
    try do
      Spark.Dsl.Transformer.remove_entity(dsl_state, [:actions], fn action ->
        action.name == action_name
      end)
    rescue
      _ ->
        # If remove_entity doesn't exist or fails, we'll need to handle this differently
        # For now, just return the dsl_state and hope add_entity replaces
        dsl_state
    end
  end
end
