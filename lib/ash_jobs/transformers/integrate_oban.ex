defmodule AshJobs.Transformers.IntegrateOban do
  @moduledoc """
  Generates Oban trigger DSL section if not already defined by user.

  This transformer creates Oban triggers for automatic workflow steps:
  - One trigger per step (unless trigger: false)
  - Triggers filter on current step state
  - Queue, retry, and error configuration from step options
  - Triggers call user-defined actions directly

  If the user has already defined an oban section, this transformer skips generation
  to preserve user customization.

  ## Generated Triggers

  For a workflow like:
      workflow do
        step :load_order do
          action :load_order
          on_success :validate_inventory
          on_error :handle_error
          queue :order_processing
          retry_attempts 3
        end

        step :process_priority do
          action :process_priority_order
          on_success :completed
          where expr(priority == :high)  # Additional filter
        end

        step :await_confirmation do
          action :send_confirmation
          trigger false  # Manual step
          on_success :completed
        end
      end

  Generates:
      oban do
        triggers do
          trigger :load_order do
            action :load_order
            where expr(state == :load_order)
            on_error :handle_error
            queue :order_processing
            max_attempts 3
          end

          trigger :process_priority do
            action :process_priority_order
            # Combined: state filter AND custom where
            where expr(state == :process_priority and priority == :high)
          end

          # No trigger for await_confirmation (trigger: false)
        end
      end
  """

  use Spark.Dsl.Transformer

  import Ash.Expr, only: [expr: 1, ref: 1]

  # Run after our own transformers but before all AshOban and AshStateMachine transformers
  def after?(AshJobs.Transformers.GenerateErrorActions), do: true
  def after?(AshJobs.Transformers.IntegrateStateMachine), do: true
  def after?(_), do: false

  def before?(AshOban.Transformers.SetDefaults), do: true
  def before?(AshOban.Transformers.DefineSchedulers), do: true
  def before?(AshOban.Transformers.DefineActionWorkers), do: true
  def before?(_), do: false

  def transform(dsl_state) do
    # Get workflow configuration
    workflow_steps = Spark.Dsl.Extension.get_entities(dsl_state, [:workflow])

    if workflow_steps && length(workflow_steps) > 0 do
      # Check workflow-level triggers option (defaults to false)
      triggers_enabled =
        Spark.Dsl.Transformer.get_option(dsl_state, [:workflow], :triggers) || false

      cond do
        # triggers: false (default) - skip all Oban trigger generation
        not triggers_enabled ->
          {:ok, dsl_state}

        # User defined their own oban config, skip generation
        has_oban_config?(dsl_state) ->
          {:ok, dsl_state}

        # triggers: true - generate triggers for steps and wrapper actions
        true ->
          dsl_state = generate_oban_triggers(dsl_state, workflow_steps)
          {:ok, dsl_state}
      end
    else
      # No workflow defined, skip
      {:ok, dsl_state}
    end
  end

  defp has_oban_config?(dsl_state) do
    # Check if triggers are configured (indicates oban section exists)
    triggers = Spark.Dsl.Extension.get_entities(dsl_state, [:oban, :triggers])
    triggers != nil && length(triggers) > 0
  end

  defp generate_oban_triggers(dsl_state, workflow_steps) do
    # Get state_attribute from workflow section (defaults to :state)
    state_attr =
      Spark.Dsl.Transformer.get_option(dsl_state, [:workflow], :state_attribute) || :state

    # Read action the generated scheduler triggers should use (e.g. a
    # `multitenancy :allow_global` action for multitenant resources). nil =
    # inherit the resource's primary read.
    read_action = Spark.Dsl.Transformer.get_option(dsl_state, [:workflow], :read_action)

    # Get the resource module for building module names
    resource_module = Spark.Dsl.Transformer.get_persisted(dsl_state, :module)

    # Get existing triggers AND scheduled_actions to avoid duplicates
    # Note: AshOban requires unique names across both triggers and scheduled_actions
    existing_triggers = Spark.Dsl.Extension.get_entities(dsl_state, [:oban, :triggers]) || []

    existing_scheduled =
      Spark.Dsl.Extension.get_entities(dsl_state, [:oban, :scheduled_actions]) || []

    existing_trigger_names = MapSet.new(existing_triggers, & &1.name)
    existing_scheduled_names = MapSet.new(existing_scheduled, & &1.name)
    existing_names = MapSet.union(existing_trigger_names, existing_scheduled_names)

    # Separate regular steps from parallel_steps
    regular_steps = Enum.reject(workflow_steps, &is_parallel_step?/1)
    parallel_steps = Enum.filter(workflow_steps, &is_parallel_step?/1)

    # Needs-gated readiness: when the resource declares a `needs` relationship,
    # the trigger for the initial (entry) state must only fire once every `need`
    # is in a success state — expressed declaratively in the trigger `where` so
    # the AshOban scheduler itself respects the DAG edges (not just the imperative
    # readiness helpers). The success-state set comes from the AshStateMachine
    # Info API so it matches what the coordinator counts.
    needs_gate = build_needs_gate(dsl_state, workflow_steps, state_attr)

    # Generate triggers for automatic regular steps only (trigger != false)
    # Skip error handler steps (they use on_complete, not on_success)
    # Skip steps that already have triggers defined
    regular_triggers =
      regular_steps
      |> Enum.reject(fn step -> step.trigger == false end)
      |> Enum.reject(&is_error_handler?/1)
      |> Enum.uniq_by(& &1.name)
      |> Enum.reject(fn step -> MapSet.member?(existing_names, step.name) end)
      |> Enum.map(
        &build_trigger(&1, state_attr, resource_module, workflow_steps, read_action, needs_gate)
      )

    # Generate triggers for wrapper actions from parallel_steps
    # ash_state_machine generates wrapper actions like :payment_process for each branch action
    wrapper_triggers =
      generate_wrapper_action_triggers(
        parallel_steps,
        state_attr,
        resource_module,
        existing_names,
        read_action
      )

    # Combine all triggers
    all_triggers = regular_triggers ++ wrapper_triggers

    # Add each trigger to the DSL state
    Enum.reduce(all_triggers, dsl_state, fn trigger, acc_state ->
      Spark.Dsl.Transformer.add_entity(
        acc_state,
        [:oban, :triggers],
        trigger
      )
    end)
  end

  defp generate_wrapper_action_triggers(
         parallel_steps,
         state_attr,
         resource_module,
         existing_names,
         read_action
       ) do
    parallel_steps
    |> Enum.flat_map(fn parallel_step ->
      # For each branch, get update actions from branch resource
      Enum.flat_map(parallel_step.branches, fn branch ->
        branch_actions =
          if AshJobs.Dsl.Entities.Branch.dynamic?(branch),
            do: [],
            else: get_branch_update_actions(branch.resource)

        Enum.map(branch_actions, fn action ->
          %{
            parallel_step: parallel_step,
            branch: branch,
            action_name: action.name,
            wrapper_action_name: :"#{branch.name}_#{action.name}"
          }
        end)
      end)
    end)
    |> Enum.reject(fn info -> MapSet.member?(existing_names, info.wrapper_action_name) end)
    |> Enum.map(&build_wrapper_trigger(&1, state_attr, resource_module, read_action))
  end

  defp get_branch_update_actions(resource) do
    resource
    |> Ash.Resource.Info.actions()
    |> Enum.filter(&(&1.type == :update))
  end

  defp build_wrapper_trigger(info, state_attr, resource_module, read_action) do
    # Filter on parent being in the parallel_step state (enter_state)
    state_where = build_state_where_expr(state_attr, info.parallel_step.name)

    # Generate module names for worker and scheduler
    worker_module = build_module_name(resource_module, info.wrapper_action_name, :Worker)
    scheduler_module = build_module_name(resource_module, info.wrapper_action_name, :Scheduler)

    # Get queue from parallel_step or default
    queue = Map.get(info.parallel_step, :queue) || :default

    opts =
      [
        name: info.wrapper_action_name,
        action: info.wrapper_action_name,
        where: state_where,
        queue: queue,
        max_attempts: 20,
        worker_opts: [],
        state: :active,
        scheduler_priority: 1,
        worker_priority: 0,
        worker_module_name: worker_module,
        scheduler_module_name: scheduler_module
      ]
      |> maybe_put_read_action(read_action)

    {:ok, trigger} =
      Spark.Dsl.Transformer.build_entity(
        AshOban,
        [:oban, :triggers],
        :trigger,
        opts
      )

    trigger
  end

  defp build_trigger(step, state_attr, resource_module, workflow_steps, read_action, needs_gate) do
    # Build where expression: state_attr == step_state
    # Use step.from (if set) as the state to match, otherwise step.name
    # If step has a custom where, combine with state filter using `and`
    step_state = step.from || step.name
    state_where = state_where_expr(state_attr, step_state, needs_gate)
    where_expr = combine_where_exprs(state_where, step.where)

    # Generate module names for worker and scheduler
    worker_module = build_module_name(resource_module, step.name, :Worker)
    scheduler_module = build_module_name(resource_module, step.name, :Scheduler)

    # Build options, only including non-nil values
    # Note: retry_attempts is number of RETRIES, so max_attempts = retries + 1 (initial attempt)
    # Default to 20 total attempts if not specified (19 retries + 1 initial)
    max_attempts = if step.retry_attempts, do: step.retry_attempts + 1, else: 20

    opts = [
      name: step.name,
      action: step.action,
      where: where_expr,
      queue: step.queue || :default,
      max_attempts: max_attempts,
      worker_opts: [],
      state: :active,
      scheduler_priority: 1,
      worker_priority: 0,
      worker_module_name: worker_module,
      scheduler_module_name: scheduler_module
    ]

    # Add optional fields only if they're not nil
    opts =
      if step.on_error do
        # Look up the action name for the error handler step
        # step.on_error is a step name, but AshOban needs the action name
        error_handler_action =
          workflow_steps
          |> Enum.find(fn s -> s.name == step.on_error end)
          |> case do
            # Fallback to step name if not found
            nil -> step.on_error
            error_step -> error_step.action
          end

        opts
        |> Keyword.put(:on_error, error_handler_action)
        # When error handler succeeds, don't fail the Oban job
        |> Keyword.put(:on_error_fails_job?, false)
      else
        opts
      end

    opts =
      if step.timeout_seconds,
        do: Keyword.put(opts, :timeout, step.timeout_seconds * 1000),
        else: opts

    opts = maybe_put_read_action(opts, read_action)

    # Use Spark.Dsl.Transformer.build_entity to properly construct the trigger
    {:ok, trigger} =
      Spark.Dsl.Transformer.build_entity(
        AshOban,
        [:oban, :triggers],
        :trigger,
        opts
      )

    trigger
  end

  # Apply the workflow's `read_action` to a generated trigger when set, so the
  # scheduler scans via that action (e.g. a `multitenancy :allow_global` read).
  defp maybe_put_read_action(opts, nil), do: opts
  defp maybe_put_read_action(opts, read_action), do: Keyword.put(opts, :read_action, read_action)

  defp build_module_name(resource_module, step_name, type) do
    # Convert step name to PascalCase for module naming
    # e.g., :load_order -> LoadOrder
    step_module_name =
      step_name
      |> Atom.to_string()
      |> Macro.camelize()

    # Build module name like: Resource.AshOban.Worker.LoadOrder
    # or: Resource.AshOban.Scheduler.LoadOrder
    Module.concat([resource_module, AshOban, type, step_module_name])
  end

  # Build the needs-gate descriptor from the dsl_state, or nil when the resource
  # declares no `needs` relationship. The gate applies to the entry (initial)
  # state — the same state `IntegrateStateMachine` picks as the initial state
  # (the first workflow step).
  defp build_needs_gate(dsl_state, workflow_steps, state_attr) do
    case AshJobs.Info.needs_relationship(dsl_state) do
      nil ->
        nil

      relationship ->
        %{
          relationship: relationship,
          success_states: success_terminal_states(dsl_state, state_attr),
          gated_state: List.first(workflow_steps).name,
          state_attr: state_attr
        }
    end
  end

  # Success terminal states, computed from the DSL state mid-transform.
  # `AshStateMachine.Info.state_machine_success_terminal_states/1` reads a
  # persisted value (`:all_state_machine_states`) that a *later* AshStateMachine
  # transformer sets — not yet available when this transformer runs — so we
  # replicate its logic from data already in the dsl: declared states with no
  # outgoing transition (terminal), minus the failure states. This matches the
  # Info API on the compiled resource, so the gate's notion of "success" matches
  # what the parallel coordinator counts.
  defp success_terminal_states(dsl_state, state_attr) do
    from_states =
      dsl_state
      |> Spark.Dsl.Extension.get_entities([:state_machine, :transitions])
      |> List.wrap()
      |> Enum.flat_map(& &1.from)
      |> MapSet.new()

    failure_states =
      Spark.Dsl.Transformer.get_option(dsl_state, [:state_machine], :failure_states) || []

    dsl_state
    |> declared_states(state_attr)
    |> Enum.reject(&MapSet.member?(from_states, &1))
    |> Kernel.--(failure_states)
  end

  defp declared_states(dsl_state, state_attr) do
    attributes = Spark.Dsl.Extension.get_entities(dsl_state, [:attributes])

    case Enum.find(attributes, &(&1.name == state_attr)) do
      nil -> []
      attribute -> Keyword.get(attribute.constraints || [], :one_of, [])
    end
  end

  # Gated entry state: ready iff the row is in the entry state AND has no unmet
  # need (no `need` in a non-success state). A row with zero needs satisfies the
  # `not exists(...)` vacuously, so it is ready immediately. The `needs` path is
  # pinned because the relationship name is configurable.
  defp state_where_expr(state_attr, step_state, %{
         gated_state: gated_state,
         relationship: relationship,
         success_states: success_states
       })
       when step_state == gated_state do
    expr(
      ^ref(state_attr) == ^step_state and
        not exists(^[relationship], ^ref(state_attr) not in ^success_states)
    )
  end

  defp state_where_expr(state_attr, step_state, _needs_gate),
    do: build_state_where_expr(state_attr, step_state)

  defp build_state_where_expr(state_attr, step_name) do
    # Build Ash filter expression: state_attr == step_name
    # Create proper structs instead of map literals
    ref = %Ash.Query.Ref{
      attribute: state_attr,
      relationship_path: [],
      resource: nil
    }

    %Ash.Query.Call{
      name: :==,
      args: [ref, step_name],
      operator?: true,
      relationship_path: []
    }
  end

  defp combine_where_exprs(state_where, nil), do: state_where

  defp combine_where_exprs(state_where, custom_where) do
    # Combine state filter with custom where using `and`
    %Ash.Query.BooleanExpression{
      op: :and,
      left: state_where,
      right: custom_where
    }
  end

  defp is_error_handler?(step) do
    # Error handlers use on_complete and have no on_success
    # Regular steps use on_success
    step.on_complete != nil && step.on_success == nil
  end

  defp is_parallel_step?(entity) do
    # Parallel steps are a different entity type that coordinate branches
    match?(%AshJobs.Dsl.Entities.ParallelStep{}, entity)
  end
end
