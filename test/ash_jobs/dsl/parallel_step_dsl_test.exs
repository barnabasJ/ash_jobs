defmodule AshJobs.Dsl.ParallelStepDslTest do
  use ExUnit.Case, async: false

  alias AshJobs.Dsl.Entities.ParallelStep

  # Define test modules for branch resources
  defmodule BranchAWorkflow do
    # Minimal module for testing - just needs to exist
  end

  defmodule BranchBWorkflow do
    # Minimal module for testing - just needs to exist
  end

  @moduledoc """
  Tests for the parallel_step DSL entity.

  These tests verify that parallel_step entities can be defined in workflows
  and that Spark correctly parses and stores them.
  """

  defp compile_resource_with_parallel_step(dsl_code) do
    # Generate unique module name to avoid conflicts
    module_name = :"TestResource#{System.unique_integer([:positive])}"

    # Create a minimal test domain
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

  describe "parallel_step DSL" do
    test "can define workflow with parallel_step" do
      {:ok, resource} =
        compile_resource_with_parallel_step("""
          workflow do
            step :start do
              action :start_action
              on_success :process_parallel
            end

            parallel_step :process_parallel do
              completion_strategy :all
              on_complete :finalize

              branch :branch_a, AshJobs.Dsl.ParallelStepDslTest.BranchAWorkflow
              branch :branch_b, AshJobs.Dsl.ParallelStepDslTest.BranchBWorkflow
            end

            step :finalize do
              action :finalize_action
              on_complete :completed
            end
          end

          actions do
            defaults [:read]
            create :create
            update :start_action
            update :finalize_action
          end
        """)

      # Verify the module compiled successfully
      assert Code.ensure_loaded?(resource)
    end

    test "Spark introspection returns parallel_step entities" do
      {:ok, resource} =
        compile_resource_with_parallel_step("""
          workflow do
            parallel_step :process_parallel do
              completion_strategy :all
              on_complete :finalize

              branch :payment, AshJobs.Dsl.ParallelStepDslTest.BranchAWorkflow
              branch :inventory, AshJobs.Dsl.ParallelStepDslTest.BranchBWorkflow
            end

            step :finalize do
              action :finalize_action
              on_complete :completed
            end
          end

          actions do
            defaults [:read]
            create :create
            update :finalize_action
          end
        """)

      # Get all workflow entities
      entities = Spark.Dsl.Extension.get_entities(resource, [:workflow])

      # Find parallel_step entities
      parallel_steps = Enum.filter(entities, &match?(%ParallelStep{}, &1))

      assert length(parallel_steps) == 1

      [parallel_step] = parallel_steps
      assert parallel_step.name == :process_parallel
      assert parallel_step.completion_strategy == :all
      assert parallel_step.on_complete == :finalize
      assert length(parallel_step.branches) == 2

      # Verify branch details
      branch_names = Enum.map(parallel_step.branches, & &1.name)
      assert :payment in branch_names
      assert :inventory in branch_names
    end

    test "can define parallel_step with different completion strategies" do
      {:ok, resource} =
        compile_resource_with_parallel_step("""
          workflow do
            parallel_step :parallel do
              completion_strategy :any
              on_complete :done

              branch :fast, AshJobs.Dsl.ParallelStepDslTest.BranchAWorkflow
              branch :slow, AshJobs.Dsl.ParallelStepDslTest.BranchBWorkflow
            end

            step :done do
              action :done_action
              on_complete :completed
            end
          end

          actions do
            defaults [:read]
            create :create
            update :done_action
          end
        """)

      entities = Spark.Dsl.Extension.get_entities(resource, [:workflow])
      parallel_steps = Enum.filter(entities, &match?(%ParallelStep{}, &1))

      [parallel_step] = parallel_steps
      assert parallel_step.completion_strategy == :any
    end

    test "can define parallel_step with require_n completion strategy" do
      {:ok, resource} =
        compile_resource_with_parallel_step("""
          workflow do
            parallel_step :parallel do
              completion_strategy {:require_n, 2}
              on_complete :done

              branch :a, AshJobs.Dsl.ParallelStepDslTest.BranchAWorkflow
              branch :b, AshJobs.Dsl.ParallelStepDslTest.BranchBWorkflow
              branch :c, AshJobs.Dsl.ParallelStepDslTest.BranchAWorkflow
            end

            step :done do
              action :done_action
              on_complete :completed
            end
          end

          actions do
            defaults [:read]
            create :create
            update :done_action
          end
        """)

      entities = Spark.Dsl.Extension.get_entities(resource, [:workflow])
      parallel_steps = Enum.filter(entities, &match?(%ParallelStep{}, &1))

      [parallel_step] = parallel_steps
      assert parallel_step.completion_strategy == {:require_n, 2}
      assert length(parallel_step.branches) == 3
    end

    test "can define parallel_step with on_error" do
      {:ok, resource} =
        compile_resource_with_parallel_step("""
          workflow do
            parallel_step :parallel do
              completion_strategy :all
              on_complete :done
              on_error :handle_error

              branch :a, AshJobs.Dsl.ParallelStepDslTest.BranchAWorkflow
            end

            step :done do
              action :done_action
              on_complete :completed
            end

            step :handle_error do
              action :error_action
              on_complete :failed
            end
          end

          actions do
            defaults [:read]
            create :create
            update :done_action
            update :error_action
          end
        """)

      entities = Spark.Dsl.Extension.get_entities(resource, [:workflow])
      parallel_steps = Enum.filter(entities, &match?(%ParallelStep{}, &1))

      [parallel_step] = parallel_steps
      assert parallel_step.on_error == :handle_error
    end
  end
end
