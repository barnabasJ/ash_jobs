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
    changeset
    |> Ash.Changeset.after_action(fn _changeset, record ->
      workflow = AshJobs.Info.workflow!(resource)
      state_attr = workflow.state_attribute || :state
      current_state = Map.get(record, state_attr)

      # Only try to trigger if workflow-level triggers are enabled
      if AshJobs.Info.triggers?(resource) do
        unless AshJobs.Readiness.terminal_state?(record) do
          case AshJobs.Info.step(resource, current_state) do
            {:ok, step} when step.trigger == true ->
              handle_trigger_result(
                AshJobs.Readiness.run_trigger_if_ready(record, current_state),
                "initial step #{current_state}"
              )

            _ ->
              :ok
          end
        end
      end

      {:ok, record}
    end)
  end

  defp handle_workflow_step(changeset, resource, step_info) do
    workflow = AshJobs.Info.workflow!(resource)
    state_attr = workflow.state_attribute || :state

    next_state = step_info.on_success || step_info.on_complete

    changeset
    |> Ash.Changeset.force_change_attribute(state_attr, next_state)
    |> Ash.Changeset.after_action(fn _changeset, record ->
      # Only try to trigger if workflow-level triggers are enabled
      if AshJobs.Info.triggers?(resource) do
        cond do
          AshJobs.Readiness.success_state?(record) ->
            AshJobs.Readiness.push_dependents(record)

          AshJobs.Readiness.terminal_state?(record) ->
            _result = AshJobs.FailurePropagation.propagate_skip(record)
            :ok

          true ->
            maybe_trigger_next_step(record, resource, next_state)
        end
      end

      {:ok, record}
    end)
  end

  defp maybe_trigger_next_step(record, resource, next_state) do
    unless AshJobs.Readiness.terminal_state?(record) do
      case AshJobs.Info.step(resource, next_state) do
        {:ok, step} when step.trigger == true ->
          handle_trigger_result(
            AshJobs.Readiness.run_trigger_if_ready(record, next_state),
            "next step #{next_state}"
          )

        _ ->
          :ok
      end
    end
  end

  defp handle_trigger_result(result, label) do
    case result do
      %Oban.Job{} ->
        :ok

      :not_ready ->
        :ok

      :terminal ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to trigger #{label}: #{inspect(reason)}")
        :ok

      _ ->
        :ok
    end
  end
end
