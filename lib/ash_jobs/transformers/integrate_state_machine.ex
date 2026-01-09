defmodule AshJobs.Transformers.IntegrateStateMachine do
  @moduledoc """
  Generates state_machine DSL section if not already defined by user.

  This transformer creates a state machine configuration based on the workflow definition:
  - One state per workflow step
  - Terminal states: :completed, :failed, :cancelled
  - Transitions based on on_success/on_error routing
  - Initial state is the first step in the workflow

  If the user has already defined a state_machine section, this transformer skips generation
  to preserve user customization.

  ## Generated State Machine

  For a workflow like:
      workflow do
        step :load_order do
          on_success :validate_inventory
          on_error :handle_error
        end

        step :validate_inventory do
          on_success :completed
        end
      end

  Generates:
      state_machine do
        initial_states [:load_order]
        default_initial_state :load_order
        state_attribute :state

        transitions do
          transition :to_validate_inventory, from: :load_order, to: :validate_inventory
          transition :to_completed, from: :validate_inventory, to: :completed
        end
      end
  """

  use Spark.Dsl.Transformer

  # Run before AshStateMachine transformers so they can process our generated DSL
  def before?(AshStateMachine.Transformers.SetDefaultInitialState), do: true
  def before?(AshStateMachine.Transformers.FillInTransitionDefaults), do: true
  def before?(AshStateMachine.Transformers.AddState), do: true
  def before?(AshStateMachine.Transformers.EnsureStateSelected), do: true
  def before?(AshStateMachine.Transformers.InjectEntryExitChanges), do: true
  def before?(_), do: false

  def transform(dsl_state) do
    # Get workflow configuration
    workflow_steps = Spark.Dsl.Extension.get_entities(dsl_state, [:workflow])

    if workflow_steps && length(workflow_steps) > 0 do
      # Check if state_machine section already exists
      if has_state_machine_config?(dsl_state) do
        # User defined their own state_machine, skip generation
        {:ok, dsl_state}
      else
        # Generate state_machine configuration
        dsl_state = generate_state_machine(dsl_state, workflow_steps)
        {:ok, dsl_state}
      end
    else
      # No workflow defined, skip
      {:ok, dsl_state}
    end
  end

  defp has_state_machine_config?(dsl_state) do
    # Check if initial_states is configured (indicates user manually configured state_machine)
    # If initial_states is present and non-empty, user has configured it
    case Spark.Dsl.Transformer.get_option(dsl_state, [:state_machine], :initial_states) do
      nil -> false
      [] -> false
      _states -> true
    end
  end

  defp generate_state_machine(dsl_state, workflow_steps) do
    # Get state_attribute from workflow section (defaults to :state)
    state_attr =
      Spark.Dsl.Transformer.get_option(dsl_state, [:workflow], :state_attribute) || :state

    # Separate regular steps from parallel_steps
    regular_steps = Enum.reject(workflow_steps, &is_parallel_step?/1)
    parallel_steps = Enum.filter(workflow_steps, &is_parallel_step?/1)

    # Collect all possible states (step names + parallel_step names + terminal states)
    step_states = Enum.map(workflow_steps, & &1.name)
    terminal_states = [:completed, :failed, :cancelled]

    # Collect target states from regular steps
    regular_referenced =
      regular_steps
      |> Enum.flat_map(fn step ->
        [step.on_success, step.on_error, step.on_complete]
        |> Enum.reject(&is_nil/1)
      end)

    # Collect target states from parallel_steps (on_complete, on_error)
    parallel_referenced =
      parallel_steps
      |> Enum.flat_map(fn ps ->
        [ps.on_complete, ps.on_error]
        |> Enum.reject(&is_nil/1)
      end)

    referenced_states =
      (regular_referenced ++ parallel_referenced)
      |> Enum.uniq()
      |> Enum.filter(fn state ->
        state in step_states or state in terminal_states
      end)

    # Combine step states and referenced states, sort for consistency
    all_states = Enum.sort(Enum.uniq(step_states ++ referenced_states))

    # Determine initial state (first step)
    initial_state = List.first(workflow_steps).name

    # Update the state attribute to have one_of constraint with all states
    dsl_state = update_state_attribute_constraints(dsl_state, state_attr, all_states)

    # Set state_machine options
    dsl_state =
      Spark.Dsl.Transformer.set_option(dsl_state, [:state_machine], :initial_states, [
        initial_state
      ])

    dsl_state =
      Spark.Dsl.Transformer.set_option(
        dsl_state,
        [:state_machine],
        :default_initial_state,
        initial_state
      )

    dsl_state =
      Spark.Dsl.Transformer.set_option(dsl_state, [:state_machine], :state_attribute, state_attr)

    # Set failure_states for proper parallel region completion detection
    dsl_state =
      Spark.Dsl.Transformer.set_option(dsl_state, [:state_machine], :failure_states, [:failed])

    # Generate and add transitions
    dsl_state = generate_transitions(dsl_state, workflow_steps)

    # Generate state entities for steps with entry/exit callbacks
    generate_state_callbacks(dsl_state, workflow_steps)
  end

  defp update_state_attribute_constraints(dsl_state, state_attr_name, all_states) do
    # Get the state attribute from DSL entities
    attributes = Spark.Dsl.Extension.get_entities(dsl_state, [:attributes])
    state_attribute = Enum.find(attributes, &(&1.name == state_attr_name))

    if state_attribute do
      # Check if user already provided one_of constraint
      existing_one_of = Keyword.get(state_attribute.constraints || [], :one_of)

      if existing_one_of do
        # User already defined one_of, don't override
        dsl_state
      else
        # Update the attribute's constraints to include one_of with all states
        updated_constraints =
          Keyword.put(state_attribute.constraints || [], :one_of, all_states)

        updated_attribute = %{state_attribute | constraints: updated_constraints}

        # Replace the attribute in the DSL state
        Spark.Dsl.Transformer.replace_entity(
          dsl_state,
          [:attributes],
          updated_attribute,
          &(&1.name == state_attr_name)
        )
      end
    else
      dsl_state
    end
  end

  defp generate_transitions(dsl_state, workflow_steps) do
    # Separate regular steps from parallel_steps
    regular_steps = Enum.reject(workflow_steps, &is_parallel_step?/1)
    parallel_steps = Enum.filter(workflow_steps, &is_parallel_step?/1)

    # Collect transitions from regular steps
    regular_transitions =
      regular_steps
      |> Enum.flat_map(fn step ->
        transitions = []

        # Add success transition
        transitions =
          if step.on_success do
            [%{action: step.action, from: [step.name], to: [step.on_success]} | transitions]
          else
            transitions
          end

        # Note: on_error is NOT a state transition - it's handled by AshOban triggers
        # The on_error option tells AshOban which action to call when a job fails
        # That error handler action is a separate workflow step with its own transition

        # Add complete transition (used by error handlers and final steps)
        transitions =
          if step.on_complete do
            [%{action: step.action, from: [step.name], to: [step.on_complete]} | transitions]
          else
            transitions
          end

        transitions
      end)

    # Collect transitions from parallel_steps
    # Parallel steps use the generated callback action (handle_{name}_complete)
    parallel_transitions =
      parallel_steps
      |> Enum.flat_map(fn ps ->
        callback_action = :"handle_#{ps.name}_complete"

        # Add on_complete transition (from parallel step to completion target)
        if ps.on_complete do
          [%{action: callback_action, from: [ps.name], to: [ps.on_complete]}]
        else
          []
        end
      end)

    # Combine and group transitions by {action, to} to combine their from states
    all_transitions =
      (regular_transitions ++ parallel_transitions)
      |> Enum.group_by(fn t -> {t.action, List.first(t.to)} end, fn t -> List.first(t.from) end)
      |> Enum.map(fn {{action, to}, froms} ->
        %{action: action, from: Enum.uniq(froms), to: [to]}
      end)

    # Add each transition
    Enum.reduce(all_transitions, dsl_state, fn transition, acc_state ->
      {:ok, transition_entity} =
        Spark.Dsl.Transformer.build_entity(
          AshStateMachine,
          [:state_machine, :transitions],
          :transition,
          action: transition.action,
          from: transition.from,
          to: transition.to
        )

      Spark.Dsl.Transformer.add_entity(
        acc_state,
        [:state_machine, :transitions],
        transition_entity
      )
    end)
  end

  defp is_parallel_step?(entity) do
    # Parallel steps are a different entity type that coordinate branches
    match?(%AshJobs.Dsl.Entities.ParallelStep{}, entity)
  end

  defp generate_state_callbacks(dsl_state, workflow_steps) do
    # Filter to regular steps that have any callbacks defined
    steps_with_callbacks =
      workflow_steps
      |> Enum.reject(&is_parallel_step?/1)
      |> Enum.filter(&has_state_callbacks?/1)

    # Add state entities for each step with callbacks
    Enum.reduce(steps_with_callbacks, dsl_state, fn step, acc_state ->
      {:ok, state_entity} =
        Spark.Dsl.Transformer.build_entity(
          AshStateMachine,
          [:state_machine, :states],
          :state,
          name: step.name,
          on_enter: step.on_enter,
          on_enter_validate: step.on_enter_validate,
          on_exit: step.on_exit,
          on_exit_validate: step.on_exit_validate
        )

      Spark.Dsl.Transformer.add_entity(
        acc_state,
        [:state_machine, :states],
        state_entity
      )
    end)
  end

  defp has_state_callbacks?(step) do
    # Check if step has any entry/exit callbacks defined
    (step.on_enter && step.on_enter != []) ||
      (step.on_enter_validate && step.on_enter_validate != []) ||
      (step.on_exit && step.on_exit != []) ||
      (step.on_exit_validate && step.on_exit_validate != [])
  end
end
