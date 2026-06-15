defmodule AshJobs.Transformers.IntegrateStateMachineTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests for the IntegrateStateMachine transformer.

  This transformer generates state_machine DSL section if not already defined by the user.
  It creates states, transitions, and routing logic based on workflow steps.
  """

  defp compile_resource_with_state_machine(dsl_code) do
    # Generate unique module name to avoid conflicts
    module_name = :"TestResource#{System.unique_integer([:positive])}"

    # Add default attributes if not present in dsl_code
    # The state attribute needs one_of constraints listing all possible states
    # For test purposes, we'll use a broad set of common states
    default_attributes = """
    attributes do
      uuid_primary_key :id
      attribute :state, :atom,
        allow_nil?: false,
        constraints: [one_of: [:load_order, :validate_inventory, :completed, :failed, :cancelled, :handle_error]]
    end
    """

    # Only add attributes if dsl_code doesn't already contain them
    dsl_with_config =
      if String.contains?(dsl_code, "attributes do") do
        dsl_code
      else
        default_attributes <> "\n" <> dsl_code
      end

    # Build full module code with both AshJobs and AshStateMachine extensions
    full_code = """
    defmodule #{module_name} do
      use Ash.Resource,
        domain: nil,
        extensions: [AshJobs, AshStateMachine]

      #{dsl_with_config}
    end
    """

    try do
      # Convert code string to AST
      quoted = Code.string_to_quoted!(full_code)

      # Evaluate the quoted code to define and compile the module
      {{:module, module, _bytecode, _return}, _binding} = Code.eval_quoted(quoted)

      {:ok, module}
    rescue
      error ->
        {:error, error}
    end
  end

  describe "state machine DSL generation" do
    test "generates state_machine section if not exists" do
      {:ok, resource} =
        compile_resource_with_state_machine("""
          attributes do
            uuid_primary_key :id
            attribute :state, :atom,
              default: :load_order,
              allow_nil?: false,
              constraints: [one_of: [:completed, :load_order]]
          end

          workflow do
            step :load_order do
              action :load_order
              on_success :completed
            end
          end

          actions do
            defaults [:read]
            update :load_order, do: accept([])
          end
        """)

      # Verify state_machine section was added
      assert {:ok, initial_states} = AshStateMachine.Info.state_machine_initial_states(resource)
      assert :load_order in initial_states
    end

    test "skips generation if state_machine section already exists" do
      {:ok, resource} =
        compile_resource_with_state_machine("""
          attributes do
            uuid_primary_key :id
            attribute :state, :atom,
              default: :custom_initial,
              allow_nil?: false,
              constraints: [one_of: [:custom_initial, :completed]]
          end

          workflow do
            step :load_order do
              action :load_order
              on_success :completed
            end
          end

          state_machine do
            initial_states [:custom_initial]
            default_initial_state :custom_initial
            state_attribute :state

            transitions do
              transition :custom, from: :custom_initial, to: :completed
            end
          end

          actions do
            defaults [:read]
            update :load_order, do: accept([])
            update :custom, do: accept([])
          end
        """)

      # User's custom state machine should be preserved
      {:ok, initial_states} = AshStateMachine.Info.state_machine_initial_states(resource)
      assert :custom_initial in initial_states
    end

    test "generates one state per workflow step" do
      {:ok, resource} =
        compile_resource_with_state_machine("""
          attributes do
            uuid_primary_key :id
            attribute :state, :atom,
              default: :load_order,
              allow_nil?: false,
              constraints: [one_of: [:completed, :load_order, :validate_inventory]]
          end

          workflow do
            step :load_order do
              action :load_order
              on_success :validate_inventory
            end

            step :validate_inventory do
              action :validate
              on_success :completed
            end
          end

          actions do
            defaults [:read]
            update :load_order, do: accept([])
            update :validate, do: accept([])
          end
        """)

      # Should have states: load_order, validate_inventory, completed
      # (plus terminal states: failed, cancelled)
      # Verify via state machine introspection
      states = AshStateMachine.Info.state_machine_all_states(resource)
      assert :load_order in states
      assert :validate_inventory in states
      assert :completed in states
    end

    test "generates transitions based on on_success routing" do
      {:ok, resource} =
        compile_resource_with_state_machine("""
          attributes do
            uuid_primary_key :id
            # Note: Error handler steps are NOT included in states - they're action containers
            # that can be called from any state, not states the workflow enters
            attribute :state, :atom,
              default: :load_order,
              allow_nil?: false,
              constraints: [one_of: [:completed, :failed, :load_order, :validate_inventory]]
          end

          workflow do
            step :load_order do
              action :load_order
              on_success :validate_inventory
              on_error :handle_error
            end

            step :validate_inventory do
              action :validate
              on_success :completed
            end

            step :handle_error do
              action :handle_error
              on_complete :failed
            end
          end

          actions do
            defaults [:read]
            update :load_order, do: accept([])
            update :validate, do: accept([])
            update :handle_error, do: accept([])
          end
        """)

      # Verify transitions exist
      # Should have: load_order → validate_inventory, validate_inventory → completed
      # Plus error transition: handle_error → failed
      transitions = AshStateMachine.Info.state_machine_transitions(resource)
      assert length(transitions) > 0

      # Find the transition for load_order action
      load_order_transition = Enum.find(transitions, &(&1.action == :load_order))
      assert load_order_transition
      assert :load_order in load_order_transition.from
      assert :validate_inventory in load_order_transition.to
    end

    test "uses custom state_attribute if specified" do
      {:ok, resource} =
        compile_resource_with_state_machine("""
          attributes do
            uuid_primary_key :id
            attribute :workflow_state, :atom,
              default: :load_order,
              allow_nil?: false,
              constraints: [one_of: [:completed, :load_order]]
          end

          workflow do
            state_attribute :workflow_state

            step :load_order do
              action :load_order
              on_success :completed
            end
          end

          actions do
            defaults [:read]
            update :load_order, do: accept([])
          end
        """)

      # Verify state attribute is :workflow_state, not :state
      state_attr = AshStateMachine.Info.state_machine_state_attribute!(resource)
      assert state_attr == :workflow_state
    end
  end
end
