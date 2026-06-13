defmodule AshJobs.Transformers.IntegrateObanTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests for the IntegrateOban transformer.

  This transformer generates Oban trigger DSL section if not already defined by the user.
  It creates triggers for automatic workflow steps with queue, retry, and error configuration.
  """

  defp compile_resource_with_oban(dsl_code) do
    # Generate unique module name to avoid conflicts
    module_name = :"TestResource#{System.unique_integer([:positive])}"

    # Create a minimal test domain for AshOban
    domain_name = :"TestDomain#{System.unique_integer([:positive])}"

    domain_code = """
    defmodule #{domain_name} do
      use Ash.Domain

      resources do
        allow_unregistered? true
      end
    end
    """

    # Evaluate domain first
    domain_quoted = Code.string_to_quoted!(domain_code)
    Code.eval_quoted(domain_quoted)

    # Add minimal default attributes if not present in dsl_code
    # Note: We don't define the state attribute here because AshStateMachine's
    # AddState transformer will create it automatically with the correct one_of
    # constraints based on the workflow definition
    default_attributes = """
    attributes do
      uuid_primary_key :id
    end
    """

    # Only add attributes if dsl_code doesn't already contain them
    dsl_with_config =
      if String.contains?(dsl_code, "attributes do") do
        dsl_code
      else
        default_attributes <> "\n" <> dsl_code
      end

    # Build full module code with AshJobs, AshStateMachine, and AshOban extensions
    # Note: domain is required for AshOban
    full_code = """
    defmodule #{module_name} do
      use Ash.Resource,
        domain: #{domain_name},
        extensions: [AshJobs, AshStateMachine, AshOban]

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

  describe "Oban trigger generation" do
    test "generates oban section if not exists" do
      {:ok, resource} =
        compile_resource_with_oban("""
          workflow do
            triggers true

            step :load_order do
              action :load_order
              on_success :completed
              queue :order_processing
            end
          end

          actions do
            defaults [:read]
            update :load_order, do: accept([])
          end
        """)

      # Verify oban triggers were added
      triggers = AshOban.Info.oban_triggers(resource)
      assert length(triggers) > 0
      assert Enum.any?(triggers, &(&1.name == :load_order))
    end

    test "skips generation if oban section already exists" do
      {:ok, resource} =
        compile_resource_with_oban("""
          workflow do
            triggers true

            step :load_order do
              action :load_order
              on_success :completed
            end
          end

          oban do
            triggers do
              trigger :custom_trigger do
                action :load_order
                where expr(state == :custom)
              end
            end
          end

          actions do
            defaults [:read]
            update :load_order, do: accept([])
          end
        """)

      # User's custom triggers should be preserved
      triggers = AshOban.Info.oban_triggers(resource)
      assert Enum.any?(triggers, &(&1.name == :custom_trigger))
    end

    test "generates one trigger per automatic step" do
      {:ok, resource} =
        compile_resource_with_oban("""
          workflow do
            triggers true

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

      triggers = AshOban.Info.oban_triggers(resource)

      # Should have triggers for: load_order, validate_inventory
      assert length(triggers) == 2
      assert Enum.any?(triggers, &(&1.name == :load_order))
      assert Enum.any?(triggers, &(&1.name == :validate_inventory))
    end

    test "skips trigger generation for manual steps (trigger: false)" do
      {:ok, resource} =
        compile_resource_with_oban("""
          workflow do
            triggers true

            step :load_order do
              action :load_order
              on_success :await_confirmation
            end

            step :await_confirmation do
              action :send_confirmation
              trigger false
              on_success :completed
            end
          end

          actions do
            defaults [:read]
            update :load_order, do: accept([])
            update :send_confirmation, do: accept([])
          end
        """)

      triggers = AshOban.Info.oban_triggers(resource)

      # Should only have trigger for load_order (not await_confirmation)
      assert length(triggers) == 1
      assert Enum.any?(triggers, &(&1.name == :load_order))
      refute Enum.any?(triggers, &(&1.name == :await_confirmation))
    end

    test "generates triggers with correct where clause" do
      {:ok, resource} =
        compile_resource_with_oban("""
          attributes do
            uuid_primary_key :id
            attribute :workflow_state, :atom,
              default: :load_order,
              allow_nil?: false,
              constraints: [one_of: [:completed, :load_order]]
          end

          workflow do
            triggers true
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

      triggers = AshOban.Info.oban_triggers(resource)
      load_trigger = Enum.find(triggers, &(&1.name == :load_order))

      # Trigger should filter on workflow_state == :load_order
      assert load_trigger.where
    end

    test "generates triggers with queue configuration" do
      {:ok, resource} =
        compile_resource_with_oban("""
          workflow do
            triggers true

            step :load_order do
              action :load_order
              on_success :completed
              queue :order_processing
            end
          end

          actions do
            defaults [:read]
            update :load_order, do: accept([])
          end
        """)

      triggers = AshOban.Info.oban_triggers(resource)
      load_trigger = Enum.find(triggers, &(&1.name == :load_order))

      assert load_trigger.queue == :order_processing
    end

    test "generates triggers with on_error routing" do
      {:ok, resource} =
        compile_resource_with_oban("""
          workflow do
            triggers true

            step :load_order do
              action :load_order
              on_success :completed
              on_error :handle_error
            end
          end

          actions do
            defaults [:read]
            update :load_order, do: accept([])
          end
        """)

      triggers = AshOban.Info.oban_triggers(resource)
      load_trigger = Enum.find(triggers, &(&1.name == :load_order))

      assert load_trigger.on_error == :handle_error
    end

    test "generates triggers with custom where clause combined with state filter" do
      {:ok, resource} =
        compile_resource_with_oban("""
          attributes do
            uuid_primary_key :id
            attribute :priority, :atom, allow_nil?: true
          end

          workflow do
            triggers true

            step :process_priority do
              action :process_order
              on_success :completed
              where expr(priority == :high)
            end
          end

          actions do
            defaults [:read]
            update :process_order, do: accept([])
          end
        """)

      triggers = AshOban.Info.oban_triggers(resource)
      trigger = Enum.find(triggers, &(&1.name == :process_priority))

      # The where should be a BooleanExpression combining state and custom where with `and`
      assert %Ash.Query.BooleanExpression{op: :and} = trigger.where

      # Left side should be the state filter
      assert %Ash.Query.Call{name: :==} = trigger.where.left

      # Right side should be the custom where (priority == :high)
      assert %Ash.Query.Call{name: :==} = trigger.where.right
    end

    test "applies the workflow read_action to every generated trigger" do
      {:ok, resource} =
        compile_resource_with_oban("""
          workflow do
            triggers true
            read_action :scheduled

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

            read :scheduled do
              multitenancy :allow_global
              pagination keyset?: true, required?: false
            end

            update :load_order, do: accept([])
            update :validate, do: accept([])
          end
        """)

      triggers = AshOban.Info.oban_triggers(resource)

      assert Enum.count(triggers) == 2
      assert Enum.all?(triggers, &(&1.read_action == :scheduled))
    end

    test "without read_action, generated triggers fall back to the default read" do
      {:ok, resource} =
        compile_resource_with_oban("""
          workflow do
            triggers true

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

      trigger = Enum.find(AshOban.Info.oban_triggers(resource), &(&1.name == :load_order))

      # Unset by AshJobs; AshOban defaults it to the primary read action.
      assert trigger.read_action in [nil, :read]
    end

    test "step without custom where has only state filter" do
      {:ok, resource} =
        compile_resource_with_oban("""
          workflow do
            triggers true

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

      triggers = AshOban.Info.oban_triggers(resource)
      trigger = Enum.find(triggers, &(&1.name == :load_order))

      # Without custom where, it should be just a Call (state == :load_order)
      assert %Ash.Query.Call{name: :==} = trigger.where
      refute match?(%Ash.Query.BooleanExpression{}, trigger.where)
    end
  end
end
