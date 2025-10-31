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

          # No trigger for await_confirmation (trigger: false)
        end
      end
  """

  use Spark.Dsl.Transformer

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
      # Check if oban section already exists
      if has_oban_config?(dsl_state) do
        # User defined their own oban config, skip generation
        {:ok, dsl_state}
      else
        # Generate oban triggers
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

    # Get existing triggers AND scheduled_actions to avoid duplicates
    # Note: AshOban requires unique names across both triggers and scheduled_actions
    existing_triggers = Spark.Dsl.Extension.get_entities(dsl_state, [:oban, :triggers]) || []

    existing_scheduled =
      Spark.Dsl.Extension.get_entities(dsl_state, [:oban, :scheduled_actions]) || []

    existing_trigger_names = MapSet.new(existing_triggers, & &1.name)
    existing_scheduled_names = MapSet.new(existing_scheduled, & &1.name)
    existing_names = MapSet.union(existing_trigger_names, existing_scheduled_names)

    # Generate triggers for automatic steps only (trigger != false)
    # Skip steps that already have triggers defined
    # Also deduplicate by step name (in case workflow_steps contains duplicates)
    triggers =
      workflow_steps
      |> Enum.reject(fn step -> step.trigger == false end)
      |> Enum.uniq_by(& &1.name)
      |> Enum.reject(fn step -> MapSet.member?(existing_names, step.name) end)
      |> Enum.map(&build_trigger(&1, state_attr))

    # Add each trigger to the DSL state
    Enum.reduce(triggers, dsl_state, fn trigger, acc_state ->
      Spark.Dsl.Transformer.add_entity(
        acc_state,
        [:oban, :triggers],
        trigger
      )
    end)
  end

  defp build_trigger(step, state_attr) do
    # Build where expression: state_attr == step_name
    where_expr = build_where_expr(state_attr, step.name)

    # Build options, only including non-nil values
    opts = [
      name: step.name,
      action: step.action,
      where: where_expr,
      queue: step.queue || :default,
      max_attempts: step.retry_attempts || 20,
      worker_opts: [],
      state: :active,
      scheduler_priority: 1,
      worker_priority: 0
    ]

    # Add optional fields only if they're not nil
    opts = if step.on_error, do: Keyword.put(opts, :on_error, step.on_error), else: opts

    opts =
      if step.timeout_seconds,
        do: Keyword.put(opts, :timeout, step.timeout_seconds * 1000),
        else: opts

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

  defp build_where_expr(state_attr, step_name) do
    # Build Ash.Expr filter: state_attr == step_name
    # We need to create the expression AST that will be evaluated by Ash
    # The expr macro expects: expr(field_name == value)
    # We use a macro to construct the expression with dynamic field name
    {:%{}, [],
     [
       __struct__: Ash.Query.Call,
       name: :==,
       args: [
         %Ash.Query.Ref{attribute: state_attr, relationship_path: []},
         step_name
       ],
       operator?: true
     ]}
  end
end
