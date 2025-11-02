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

    # Collect all possible states (step names + terminal states)
    step_states = Enum.map(workflow_steps, & &1.name)
    terminal_states = [:completed, :failed, :cancelled]

    # Collect target states that are actually steps or terminal states
    referenced_states =
      workflow_steps
      |> Enum.flat_map(fn step ->
        [step.on_success, step.on_error, step.on_complete]
        |> Enum.reject(&is_nil/1)
      end)
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

    # Generate and add transitions
    generate_transitions(dsl_state, workflow_steps)
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
    # Collect all transitions from workflow steps
    transitions =
      workflow_steps
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
      # Group transitions by {action, to} and combine their from states
      |> Enum.group_by(fn t -> {t.action, List.first(t.to)} end, fn t -> List.first(t.from) end)
      |> Enum.map(fn {{action, to}, froms} ->
        %{action: action, from: Enum.uniq(froms), to: [to]}
      end)

    # Add each transition
    Enum.reduce(transitions, dsl_state, fn transition, acc_state ->
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
end
