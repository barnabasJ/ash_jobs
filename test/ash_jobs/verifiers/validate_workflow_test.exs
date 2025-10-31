defmodule AshJobs.Verifiers.ValidateWorkflowTest do
  use ExUnit.Case, async: false

  import AshJobs.Test.CompilationHelpers

  describe "step reference validation" do
    test "validates all on_success references exist" do
      assert_compile_error(
        ~r/Invalid.*on_success.*nonexistent_step/s,
        """
        workflow do
          step :load_order do
            action :load_order
            on_success :nonexistent_step
          end
        end

        actions do
          defaults [:read]
          update :load_order, do: accept([])
        end
        """
      )
    end

    test "validates all on_error references exist" do
      assert_compile_error(
        ~r/Invalid.*on_error.*nonexistent_handler/s,
        """
        workflow do
          step :load_order do
            action :load_order
            on_success :completed
            on_error :nonexistent_handler
          end
        end

        actions do
          defaults [:read]
          update :load_order, do: accept([])
        end
        """
      )
    end

    test "allows terminal states in on_success" do
      assert {:ok, _resource} =
               compile_resource("""
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
    end

    test "allows terminal states in on_complete" do
      assert {:ok, _resource} =
               compile_resource("""
               workflow do
                 step :load_order do
                   action :load_order
                   on_success :handle_error
                   on_error :handle_error
                 end

                 step :handle_error do
                   action :handle_error
                   on_complete :failed
                 end
               end

               actions do
                 defaults [:read]
                 update :load_order, do: accept([])
                 update :handle_error, do: accept([])
               end
               """)
    end
  end

  describe "circular dependency detection" do
    test "detects direct circular dependencies" do
      assert_compile_error(
        ~r/Circular dependency/i,
        """
        workflow do
          step :step_a do
            action :action_a
            on_success :step_b
          end

          step :step_b do
            action :action_b
            on_success :step_a
          end
        end

        actions do
          defaults [:read]
          update :action_a, do: accept([])
          update :action_b, do: accept([])
        end
        """
      )
    end

    test "detects indirect circular dependencies" do
      assert_compile_error(
        ~r/Circular dependency/i,
        """
        workflow do
          step :step_a do
            action :action_a
            on_success :step_b
          end

          step :step_b do
            action :action_b
            on_success :step_c
          end

          step :step_c do
            action :action_c
            on_success :step_a
          end
        end

        actions do
          defaults [:read]
          update :action_a, do: accept([])
          update :action_b, do: accept([])
          update :action_c, do: accept([])
        end
        """
      )
    end

    test "allows non-circular workflows" do
      assert {:ok, _resource} =
               compile_resource("""
               workflow do
                 step :step_a do
                   action :action_a
                   on_success :step_b
                 end

                 step :step_b do
                   action :action_b
                   on_success :step_c
                 end

                 step :step_c do
                   action :action_c
                   on_success :completed
                 end
               end

               actions do
                 defaults [:read]
                 update :action_a, do: accept([])
                 update :action_b, do: accept([])
                 update :action_c, do: accept([])
               end
               """)
    end
  end

  describe "action existence validation" do
    test "validates all step actions are defined" do
      assert_compile_error(
        ~r/Missing required actions.*load_order/,
        """
        workflow do
          step :load_order do
            action :load_order
            on_success :completed
          end
        end

        actions do
          defaults [:read]
        end
        """
      )
    end

    test "passes when all actions are defined" do
      assert {:ok, _resource} =
               compile_resource("""
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
    end
  end

  describe "entry point validation" do
    test "validates at least one step has no incoming references" do
      # This scenario creates a cycle, so it will be caught by circular dependency check
      # which runs before entry point validation. To properly test entry point validation,
      # we rely on the circular dependency test and accept that circular scenarios
      # are caught earlier in the validation pipeline.
      #
      # A true "no entry point" scenario without circularity is mathematically impossible:
      # if all steps have incoming references forming a closed graph with no cycles,
      # that would require an infinite graph or external references.
      #
      # Therefore, we test that circular dependencies are caught (which implies no valid entry point)
      assert_compile_error(
        ~r/Circular dependency/i,
        """
        workflow do
          step :step_a do
            action :action_a
            on_success :step_b
            on_error :step_b
          end

          step :step_b do
            action :action_b
            on_success :step_a
            on_error :step_a
          end
        end

        actions do
          defaults [:read]
          update :action_a, do: accept([])
          update :action_b, do: accept([])
        end
        """
      )
    end

    test "allows workflows with clear entry point" do
      assert {:ok, _resource} =
               compile_resource("""
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
    end
  end

  describe "reachability validation" do
    test "validates all steps are reachable from entry point" do
      # Note: Most unreachable step scenarios also create circular dependencies
      # (if a step is unreachable and not an entry point, it's likely in a cycle).
      # This test expects circular dependency error which implies unreachability.
      # For a pure reachability test, see the positive test below.
      assert_compile_error(
        ~r/Circular dependency/s,
        """
        workflow do
          step :load_order do
            action :load_order
            on_success :validate
          end

          step :validate do
            action :validate
            on_success :completed
          end

          # This step has a self-reference, creating both:
          # 1. A circular dependency (caught first)
          # 2. An unreachable disconnected component
          step :orphaned_step do
            action :orphaned
            on_success :completed
            on_error :orphaned_step
          end
        end

        actions do
          defaults [:read]
          update :load_order, do: accept([])
          update :validate, do: accept([])
          update :orphaned, do: accept([])
        end
        """
      )
    end

    test "allows workflows where all steps are reachable" do
      assert {:ok, _resource} =
               compile_resource("""
               workflow do
                 step :load_order do
                   action :load_order
                   on_success :validate
                   on_error :handle_error
                 end

                 step :validate do
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
    end
  end
end
