defmodule AshJobs.Dsl.ParallelStepDslTest do
  use ExUnit.Case, async: false

  alias AshJobs.Dsl.Entities.ParallelStep

  # Define test modules for branch resources - must be actual Ash.Resource modules
  # for ash_state_machine's GenerateRegionActions transformer to work
  defmodule BranchDomain do
    use Ash.Domain

    resources do
      allow_unregistered? true
    end
  end

  defmodule BranchAWorkflow do
    use Ash.Resource,
      domain: AshJobs.Dsl.ParallelStepDslTest.BranchDomain,
      extensions: [AshJobs, AshStateMachine, AshOban]

    attributes do
      uuid_primary_key :id
      attribute :parent_id, :uuid, public?: true
    end

    workflow do
      step :work do
        action :do_work
        on_success(:completed)
      end
    end

    actions do
      defaults [:read]
      create :create, do: accept([:parent_id])
      update :do_work, do: accept([])
    end
  end

  defmodule BranchBWorkflow do
    use Ash.Resource,
      domain: AshJobs.Dsl.ParallelStepDslTest.BranchDomain,
      extensions: [AshJobs, AshStateMachine, AshOban]

    attributes do
      uuid_primary_key :id
      attribute :parent_id, :uuid, public?: true
    end

    workflow do
      step :work do
        action :do_work
        on_success(:completed)
      end
    end

    actions do
      defaults [:read]
      create :create, do: accept([:parent_id])
      update :do_work, do: accept([])
    end
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
    @tag story: "US-SPS-01"
    test "can define workflow with parallel_step" do
      # Given an author declares a workflow with a fixed-resource parallel_step
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
            create :create, do: accept([])
            update :start_action, do: accept([])
            update :finalize_action, do: accept([])
          end
        """)

      # When the resource compiles with AshJobs, AshStateMachine, and AshOban
      # Then the resource loads successfully
      assert Code.ensure_loaded?(resource)
    end

    @tag story: "US-SPS-01"
    test "Spark introspection returns parallel_step entities" do
      # Given an author declares a parallel_step with two fixed-resource branches
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
            create :create, do: accept([])
            update :finalize_action, do: accept([])
          end
        """)

      # When the resource compiles and we introspect its workflow entities
      entities = Spark.Dsl.Extension.get_entities(resource, [:workflow])
      parallel_steps = Enum.filter(entities, &match?(%ParallelStep{}, &1))

      # Then introspection returns the ParallelStep with its name, on_complete,
      # completion strategy, and declared branch list intact
      assert length(parallel_steps) == 1

      [parallel_step] = parallel_steps
      assert parallel_step.name == :process_parallel
      assert parallel_step.completion_strategy == :all
      assert parallel_step.on_complete == :finalize
      assert length(parallel_step.branches) == 2

      branch_names = Enum.map(parallel_step.branches, & &1.name)
      assert :payment in branch_names
      assert :inventory in branch_names
    end

    @tag story: "US-SPS-02"
    test "can define parallel_step with different completion strategies" do
      # Given an author declares a parallel_step with the :any completion strategy
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
            create :create, do: accept([])
            update :done_action, do: accept([])
          end
        """)

      # When the workflow DSL compiles and we introspect it
      entities = Spark.Dsl.Extension.get_entities(resource, [:workflow])
      parallel_steps = Enum.filter(entities, &match?(%ParallelStep{}, &1))

      # Then the ParallelStep retains the chosen :any completion strategy
      [parallel_step] = parallel_steps
      assert parallel_step.completion_strategy == :any
    end

    @tag story: "US-SPS-02"
    test "can define parallel_step with require_n completion strategy" do
      # Given an author declares a parallel_step with {:require_n, 2} over three branches
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
            create :create, do: accept([])
            update :done_action, do: accept([])
          end
        """)

      # When the workflow DSL compiles and we introspect it
      entities = Spark.Dsl.Extension.get_entities(resource, [:workflow])
      parallel_steps = Enum.filter(entities, &match?(%ParallelStep{}, &1))

      # Then the ParallelStep retains {:require_n, 2} bounded by its 3 static branches
      [parallel_step] = parallel_steps
      assert parallel_step.completion_strategy == {:require_n, 2}
      assert length(parallel_step.branches) == 3
    end

    @tag story: "US-SPS-03"
    test "can define parallel_step with on_error" do
      # Given an author declares a parallel_step with on_error :handle_error
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
            create :create, do: accept([])
            update :done_action, do: accept([])
            update :error_action, do: accept([])
          end
        """)

      # When the workflow DSL compiles (state-machine integration runs without
      # crashing on the :from-less parallel step) and we introspect it
      entities = Spark.Dsl.Extension.get_entities(resource, [:workflow])
      parallel_steps = Enum.filter(entities, &match?(%ParallelStep{}, &1))

      # Then the ParallelStep retains its on_error routing target
      [parallel_step] = parallel_steps
      assert parallel_step.on_error == :handle_error
    end
  end
end
