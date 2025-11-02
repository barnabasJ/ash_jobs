defmodule AshJobs.Change do
  @moduledoc """
  Global Change module automatically added to all workflow actions.

  Responsibilities:
  1. Detect current workflow step
  2. Transition to next state (on_success)
  3. Schedule next Oban job
  4. Emit telemetry events

  IMPORTANT: Runs in after_transaction hook, so only executes on success.
  Error routing handled by Oban trigger's on_error option.
  """
  use Ash.Resource.Change
  require Logger

  def change(changeset, _opts, _context) do
    # Detect which step this action belongs to
    resource = changeset.resource
    action_name = changeset.action.name
    action_type = changeset.action.type

    case AshJobs.Info.get_step_for_action(resource, action_name) do
      :error ->
        # Not a workflow step action
        # If this is a create action, trigger the initial workflow step
        if action_type == :create do
          handle_create_action(changeset, resource)
        else
          # Not a workflow action and not a create, skip
          changeset
        end

      {:ok, step_info} ->
        # This is a workflow step action
        handle_workflow_step(changeset, resource, step_info)
    end
  end

  defp handle_create_action(changeset, resource) do
    # For create actions, trigger the initial workflow step
    # The state should already be set to the initial state by the user or defaults
    changeset
    |> Ash.Changeset.after_action(fn _changeset, record ->
      # Get the current state from the record
      workflow = AshJobs.Info.workflow!(resource)
      state_attr = workflow.state_attribute || :state
      current_state = Map.get(record, state_attr)

      # Trigger the workflow step for the current (initial) state
      # Don't trigger if we're in a terminal state
      unless current_state in [:completed, :failed, :cancelled] do
        case AshOban.run_trigger(record, current_state) do
          %Oban.Job{} = _job ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to trigger initial step #{current_state}: #{inspect(reason)}")
            :ok
        end
      end

      {:ok, record}
    end)
  end

  defp handle_workflow_step(changeset, resource, step_info) do
    workflow = AshJobs.Info.workflow!(resource)
    state_attr = workflow.state_attribute || :state

    # Determine the next state - prefer on_success, fall back to on_complete
    # on_complete is used for error handlers that always go to a terminal state
    next_state = step_info.on_success || step_info.on_complete

    changeset
    |> Ash.Changeset.force_change_attribute(state_attr, next_state)
    |> Ash.Changeset.after_action(fn _changeset, record ->
      # Trigger the next step immediately using AshOban.run_trigger
      # This schedules the Oban job for the next workflow step
      # Don't trigger if we're going to a terminal state
      unless next_state in [:completed, :failed, :cancelled] do
        case AshOban.run_trigger(record, next_state) do
          %Oban.Job{} = _job ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to trigger next step #{next_state}: #{inspect(reason)}")
            :ok
        end
      end

      {:ok, record}
    end)
  end
end
