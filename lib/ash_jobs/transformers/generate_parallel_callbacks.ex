defmodule AshJobs.Transformers.GenerateParallelCallbacks do
  @moduledoc """
  Generates completion callback actions for parallel_steps.

  For each parallel_step, this transformer generates the completion callback
  action that is invoked by AshStateMachine when the parallel region's
  completion strategy is satisfied.

  ## Generated Actions

  Completion callback actions are generated with:
  - Name: `handle_{parallel_step_name}_complete`
  - Type: update action
  - `accept []` - No direct attribute changes
  - `require_atomic? false` - Allow non-atomic updates

  ## Example

  Given:
      parallel_step :process_order do
        completion_strategy :all
        on_complete :finalize

        branch :payment, PaymentWorkflow
        branch :inventory, InventoryWorkflow
      end

  Generates:
      update :handle_process_order_complete do
        accept []
        require_atomic? false
      end

  The AshStateMachine parallel region support calls this action when the
  completion strategy is satisfied. The state transition to :finalize is
  handled by the state machine transitions.
  """

  use Spark.Dsl.Transformer

  # Run before IntegrateStateMachine so the action exists for transition generation
  def before?(AshJobs.Transformers.IntegrateStateMachine), do: true
  def before?(AshJobs.Transformers.IntegrateParallelRegions), do: true
  def before?(_), do: false

  # Run after GenerateErrorActions to maintain ordering
  def after?(AshJobs.Transformers.GenerateErrorActions), do: true
  def after?(_), do: false

  def transform(dsl_state) do
    # Get workflow entities
    workflow_entities = Spark.Dsl.Extension.get_entities(dsl_state, [:workflow])

    # Filter to parallel_steps only
    parallel_steps = Enum.filter(workflow_entities, &is_parallel_step?/1)

    if Enum.any?(parallel_steps) do
      # Generate callback actions for each parallel_step
      dsl_state = generate_callback_actions(dsl_state, parallel_steps)
      {:ok, dsl_state}
    else
      # No parallel_steps defined, skip
      {:ok, dsl_state}
    end
  end

  defp is_parallel_step?(entity) do
    match?(%AshJobs.Dsl.Entities.ParallelStep{}, entity)
  end

  defp generate_callback_actions(dsl_state, parallel_steps) do
    existing_actions = Ash.Resource.Info.actions(dsl_state)
    existing_action_names = MapSet.new(existing_actions, & &1.name)

    parallel_steps
    |> Enum.map(fn ps -> callback_action_name(ps.name) end)
    |> Enum.reject(&MapSet.member?(existing_action_names, &1))
    |> Enum.reduce(dsl_state, fn action_name, acc_state ->
      add_callback_action(acc_state, action_name)
    end)
  end

  defp callback_action_name(parallel_step_name) do
    :"handle_#{parallel_step_name}_complete"
  end

  defp add_callback_action(dsl_state, action_name) do
    # Build callback action using Spark entity builders
    # State transitions are handled by the state machine
    case Ash.Resource.Builder.build_action(
           :update,
           action_name,
           accept: [],
           require_atomic?: false
         ) do
      {:ok, action} ->
        # Add action to DSL state using Spark.Dsl.Transformer
        Spark.Dsl.Transformer.add_entity(dsl_state, [:actions], action)

      {:error, error} ->
        raise "Failed to build parallel callback action #{action_name}: #{inspect(error)}"
    end
  end
end
