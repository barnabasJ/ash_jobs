defmodule AshJobs.Transformers.GenerateErrorActionsTest do
  use ExUnit.Case, async: false

  import AshJobs.Test.CompilationHelpers

  describe "error action generation" do
    test "generates error handler actions for on_error steps" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :load_order do
              action :load_full_order
              on_success :completed
              on_error :handle_load_error
            end

            step :handle_load_error do
              action :handle_load_error
              on_complete :failed
            end
          end

          actions do
            defaults [:read]
            update :load_full_order do
              accept []
            end
          end
        """)

      # Check that error handler action was generated
      actions = Ash.Resource.Info.actions(resource)
      error_action = Enum.find(actions, &(&1.name == :handle_load_error))

      assert error_action
      assert error_action.type == :update
    end

    test "skips generation if error handler action already exists" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :load_order do
              action :load_full_order
              on_success :completed
              on_error :handle_load_error
            end

            step :handle_load_error do
              action :handle_load_error
              on_complete :failed
            end
          end

          actions do
            defaults [:read]

            update :load_full_order do
              accept []
            end

            # User-defined error handler
            update :handle_load_error do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      error_actions = Enum.filter(actions, &(&1.name == :handle_load_error))

      # Should only have one (the user-defined one)
      assert length(error_actions) == 1
    end

    test "generates error actions with proper error argument" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :load_order do
              action :load_full_order
              on_success :completed
              on_error :handle_load_error
            end

            step :handle_load_error do
              action :handle_load_error
              on_complete :failed
            end
          end

          actions do
            defaults [:read]
            update :load_full_order do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      error_action = Enum.find(actions, &(&1.name == :handle_load_error))

      # Verify it has an error argument
      assert error_action
      error_arg = Enum.find(error_action.arguments, &(&1.name == :error))
      assert error_arg
      assert error_arg.type == :term
      assert error_arg.allow_nil? == true
    end

    test "generates error actions without changes (routing handled by AshJobs.Change)" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :load_order do
              action :load_full_order
              on_success :completed
              on_error :handle_load_error
            end

            step :handle_load_error do
              action :handle_load_error
              on_complete :failed
            end
          end

          actions do
            defaults [:read]
            update :load_full_order do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      error_action = Enum.find(actions, &(&1.name == :handle_load_error))

      # Generated error actions should have no changes initially
      # State transitions are handled by AshJobs.Change module via on_complete
      # Note: BuildWorkflow transformer will add AshJobs.Change to the changes list
      assert error_action

      # Find changes that are NOT AshJobs.Change (those added by GenerateErrorActions)
      non_workflow_changes =
        Enum.reject(error_action.changes, fn change ->
          match?(%Ash.Resource.Change{change: {AshJobs.Change, _}}, change)
        end)

      # Should have no changes from GenerateErrorActions
      assert non_workflow_changes == []
    end

    test "generates error actions with require_atomic? set to false" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :load_order do
              action :load_full_order
              on_success :completed
              on_error :handle_load_error
            end

            step :handle_load_error do
              action :handle_load_error
              on_complete :failed
            end
          end

          actions do
            defaults [:read]
            update :load_full_order do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      error_action = Enum.find(actions, &(&1.name == :handle_load_error))

      assert error_action
      assert error_action.require_atomic? == false
    end

    test "generates multiple error actions for multiple error handlers" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :load_order do
              action :load_full_order
              on_success :validate_inventory
              on_error :handle_load_error
            end

            step :validate_inventory do
              action :check_stock
              on_success :completed
              on_error :handle_inventory_error
            end

            step :handle_load_error do
              action :handle_load_error
              on_complete :failed
            end

            step :handle_inventory_error do
              action :handle_inventory_error
              on_complete :failed
            end
          end

          actions do
            defaults [:read]

            update :load_full_order do
              accept []
            end

            update :check_stock do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      load_error_action = Enum.find(actions, &(&1.name == :handle_load_error))
      inventory_error_action = Enum.find(actions, &(&1.name == :handle_inventory_error))

      assert load_error_action
      assert inventory_error_action
    end

    test "does not generate duplicate actions for same error handler" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :load_order do
              action :load_full_order
              on_success :validate_inventory
              on_error :handle_error
            end

            step :validate_inventory do
              action :check_stock
              on_success :completed
              on_error :handle_error
            end

            step :handle_error do
              action :handle_error
              on_complete :failed
            end
          end

          actions do
            defaults [:read]

            update :load_full_order do
              accept []
            end

            update :check_stock do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      error_actions = Enum.filter(actions, &(&1.name == :handle_error))

      # Should only have one error handler action even though two steps reference it
      assert length(error_actions) == 1
    end

    test "skips generation when no workflow is defined" do
      {:ok, resource} =
        compile_resource("""
          actions do
            defaults [:read]

            update :some_action do
              accept []
            end
          end
        """)

      # Should compile successfully without errors
      assert resource
    end

    test "skips generation when workflow has no error handlers" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :load_order do
              action :load_full_order
              on_success :completed
            end
          end

          actions do
            defaults [:read]

            update :load_full_order do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)

      # Should only have the defined actions, no generated error handlers
      action_names = Enum.map(actions, & &1.name)
      refute :handle_load_error in action_names
    end
  end
end
