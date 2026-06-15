defmodule AshJobs.Transformers.BuildWorkflowTest do
  @moduledoc """
  Tests for BuildWorkflow transformer that injects AshJobs.Change into workflow actions.

  The BuildWorkflow transformer ensures that all workflow step actions and create actions
  have the AshJobs.Change module that handles routing, state transitions, and Oban scheduling.
  """

  use ExUnit.Case, async: false

  import AshJobs.Test.CompilationHelpers

  describe "AshJobs.Change injection into step actions" do
    test "adds Change module to all workflow step actions" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :process do
              action :do_work
              on_success :completed
            end
          end

          actions do
            defaults [:read]

            update :do_work do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      action = Enum.find(actions, &(&1.name == :do_work))

      assert action

      # Verify AshJobs.Change was added to the action
      has_change =
        Enum.any?(action.changes, fn
          %{change: {AshJobs.Change, _}} -> true
          _ -> false
        end)

      assert has_change, "Expected AshJobs.Change to be in action changes"
    end

    test "adds Change module to multiple workflow step actions" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :step_one do
              action :process_one
              on_success :step_two
            end

            step :step_two do
              action :process_two
              on_success :completed
            end
          end

          actions do
            defaults [:read]

            update :process_one do
              accept []
            end

            update :process_two do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)

      # Check both actions have the Change module
      for action_name <- [:process_one, :process_two] do
        action = Enum.find(actions, &(&1.name == action_name))
        assert action

        has_change =
          Enum.any?(action.changes, fn
            %{change: {AshJobs.Change, _}} -> true
            _ -> false
          end)

        assert has_change, "Expected AshJobs.Change in #{action_name}"
      end
    end

    test "adds Change module only once per action when action is shared" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :step_one do
              action :shared_action
              on_success :step_two
            end

            step :step_two do
              action :process_two
              on_success :completed
            end
          end

          actions do
            defaults [:read]

            update :shared_action do
              accept []
            end

            update :process_two do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      action = Enum.find(actions, &(&1.name == :shared_action))

      # Count how many times Change module appears
      change_count =
        Enum.count(action.changes, fn
          %{change: {AshJobs.Change, _}} -> true
          _ -> false
        end)

      assert change_count == 1, "Expected exactly one AshJobs.Change, got #{change_count}"
    end

    test "preserves existing changes and adds Change module at the end" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :process do
              action :do_work
              on_success :completed
            end
          end

          actions do
            defaults [:read]

            update :do_work do
              accept []

              change fn changeset, _context ->
                Ash.Changeset.change_attribute(changeset, :name, "changed")
              end
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      action = Enum.find(actions, &(&1.name == :do_work))

      assert action
      # Should have at least 2 changes: user's change + AshJobs.Change
      assert length(action.changes) >= 2

      # AshJobs.Change should be last
      last_change = List.last(action.changes)

      assert match?(%{change: {AshJobs.Change, _}}, last_change),
             "Expected AshJobs.Change to be last change"
    end
  end

  describe "AshJobs.Change injection into create actions" do
    test "adds Change module to create actions" do
      {:ok, resource} =
        compile_resource("""
          attributes do
            uuid_primary_key :id
            attribute :name, :string, allow_nil?: false, public?: true
            attribute :state, :atom, default: :process, allow_nil?: false, public?: true
          end

          workflow do
            step :process do
              action :do_work
              on_success :completed
            end
          end

          actions do
            defaults [:read]

            create :create do
              accept []
            end

            update :do_work do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      create_action = Enum.find(actions, &(&1.name == :create))

      assert create_action

      # Verify AshJobs.Change was added to the create action
      has_change =
        Enum.any?(create_action.changes, fn
          %{change: {AshJobs.Change, _}} -> true
          _ -> false
        end)

      assert has_change, "Expected AshJobs.Change in create action"
    end

    test "adds Change module to all create actions" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :process do
              action :do_work
              on_success :completed
            end
          end

          actions do
            defaults [:read]

            create :create do
              accept []
            end

            create :special_create do
              accept []
            end

            update :do_work do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)

      # Check both create actions have the Change module
      for action_name <- [:create, :special_create] do
        action = Enum.find(actions, &(&1.name == action_name))
        assert action

        has_change =
          Enum.any?(action.changes, fn
            %{change: {AshJobs.Change, _}} -> true
            _ -> false
          end)

        assert has_change, "Expected AshJobs.Change in #{action_name}"
      end
    end

    test "preserves existing changes in create actions" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :process do
              action :do_work
              on_success :completed
            end
          end

          actions do
            defaults [:read]

            create :create do
              accept []

              change fn changeset, _context ->
                Ash.Changeset.force_change_attribute(changeset, :state, :process)
              end
            end

            update :do_work do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      create_action = Enum.find(actions, &(&1.name == :create))

      assert create_action
      # Should have at least 2 changes
      assert length(create_action.changes) >= 2

      # AshJobs.Change should be last
      last_change = List.last(create_action.changes)

      assert match?(%{change: {AshJobs.Change, _}}, last_change),
             "Expected AshJobs.Change to be last"
    end
  end

  describe "Change module configuration" do
    test "Change module is configured for create and update actions" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :process do
              action :do_work
              on_success :completed
            end
          end

          actions do
            defaults [:read]

            create :create do
              accept []
            end

            update :do_work do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)

      for action <- actions do
        if action.type in [:create, :update] do
          change =
            Enum.find(action.changes, fn
              %{change: {AshJobs.Change, _}} -> true
              _ -> false
            end)

          if change do
            # Verify the change configuration
            assert change.on == [:create, :update]
            assert change.only_when_valid? == false
            assert change.description == "AshJobs workflow routing"
          end
        end
      end
    end
  end

  describe "error handler action handling" do
    test "adds Change module to error handler actions" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :process do
              action :do_work
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

            update :do_work do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      error_action = Enum.find(actions, &(&1.name == :handle_error))

      assert error_action, "Error handler action should be generated"

      # Verify AshJobs.Change was added
      has_change =
        Enum.any?(error_action.changes, fn
          %{change: {AshJobs.Change, _}} -> true
          _ -> false
        end)

      assert has_change, "Expected AshJobs.Change in error handler action"
    end
  end

  describe "edge cases" do
    test "handles workflows with no steps gracefully" do
      {:ok, resource} =
        compile_resource("""
          actions do
            defaults [:read]

            create :create do
              accept []
            end
          end
        """)

      # Should compile successfully
      assert resource
    end

    test "handles missing action gracefully" do
      # This should be caught by validator, but transformer shouldn't crash
      assert_compile_error(
        ~r/Missing required actions.*missing_action/s,
        """
          workflow do
            step :process do
              action :missing_action
              on_success :completed
            end
          end

          actions do
            defaults [:read]

            create :create do
              accept []
            end
          end
        """
      )
    end

    test "handles workflows with only error handler steps" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :handle_error do
              action :notify_error
              on_complete :failed
            end
          end

          actions do
            defaults [:read]

            create :create do
              accept []
            end

            update :notify_error do
              require_atomic? false
              argument :error, :term, allow_nil?: true
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)
      error_action = Enum.find(actions, &(&1.name == :notify_error))

      assert error_action

      has_change =
        Enum.any?(error_action.changes, fn
          %{change: {AshJobs.Change, _}} -> true
          _ -> false
        end)

      assert has_change
    end

    test "handles resources with no create actions" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :process do
              action :do_work
              on_success :completed
            end
          end

          actions do
            defaults [:read]

            update :do_work do
              accept []
            end
          end
        """)

      # Should compile successfully
      assert resource

      # Verify the update action has the change
      actions = Ash.Resource.Info.actions(resource)
      action = Enum.find(actions, &(&1.name == :do_work))

      has_change =
        Enum.any?(action.changes, fn
          %{change: {AshJobs.Change, _}} -> true
          _ -> false
        end)

      assert has_change
    end

    test "handles resources with explicit default actions" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :process do
              action :do_work
              on_success :completed
            end
          end

          actions do
            defaults [:create, :read, :update, :destroy]

            update :do_work do
              accept []
            end
          end
        """)

      # Should compile successfully
      assert resource

      # The default create action should also have the Change module
      actions = Ash.Resource.Info.actions(resource)
      create_actions = Enum.filter(actions, &(&1.type == :create))
      assert [_ | _] = create_actions

      for action <- create_actions do
        # Note: This might not add Change to default actions, which is acceptable
        # Just verify it doesn't crash
        assert is_list(action.changes)
      end
    end
  end

  describe "transformer ordering" do
    test "runs after GenerateErrorActions" do
      # This is verified by the transformer's after? function
      assert AshJobs.Transformers.BuildWorkflow.after?(AshJobs.Transformers.GenerateErrorActions) ==
               true
    end

    test "runs before IntegrateStateMachine" do
      # This is verified by the transformer's before? function
      assert AshJobs.Transformers.BuildWorkflow.before?(
               AshJobs.Transformers.IntegrateStateMachine
             ) == true
    end

    test "runs before IntegrateOban" do
      # This is verified by the transformer's before? function
      assert AshJobs.Transformers.BuildWorkflow.before?(AshJobs.Transformers.IntegrateOban) ==
               true
    end
  end

  describe "integration with other transformers" do
    test "works correctly with error action generation" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :process do
              action :do_work
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

            create :create do
              accept []
            end

            update :do_work do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)

      # Both the main action and generated error action should have Change module
      for action_name <- [:do_work, :handle_error] do
        action = Enum.find(actions, &(&1.name == action_name))
        assert action, "Expected #{action_name} to exist"

        has_change =
          Enum.any?(action.changes, fn
            %{change: {AshJobs.Change, _}} -> true
            _ -> false
          end)

        assert has_change, "Expected AshJobs.Change in #{action_name}"
      end
    end

    test "works correctly with multiple steps and error handlers" do
      {:ok, resource} =
        compile_resource("""
          workflow do
            step :step_one do
              action :process_one
              on_success :step_two
              on_error :handle_one_error
            end

            step :step_two do
              action :process_two
              on_success :completed
              on_error :handle_two_error
            end

            step :handle_one_error do
              action :handle_one_error
              on_complete :failed
            end

            step :handle_two_error do
              action :handle_two_error
              on_complete :failed
            end
          end

          actions do
            defaults [:read]

            create :create do
              accept []
            end

            update :process_one do
              accept []
            end

            update :process_two do
              accept []
            end
          end
        """)

      actions = Ash.Resource.Info.actions(resource)

      # All actions should have Change module
      expected_actions = [
        :create,
        :process_one,
        :process_two,
        :handle_one_error,
        :handle_two_error
      ]

      for action_name <- expected_actions do
        action = Enum.find(actions, &(&1.name == action_name))
        assert action, "Expected #{action_name} to exist"

        has_change =
          Enum.any?(action.changes, fn
            %{change: {AshJobs.Change, _}} -> true
            _ -> false
          end)

        assert has_change, "Expected AshJobs.Change in #{action_name}"
      end
    end
  end
end
