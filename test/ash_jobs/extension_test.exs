defmodule AshJobs.ExtensionTest do
  use ExUnit.Case, async: true

  alias AshJobs

  describe "AshJobs extension" do
    test "is a Spark DSL extension" do
      assert function_exported?(AshJobs, :sections, 0)
    end

    test "exports workflow section" do
      sections = AshJobs.sections()
      assert Enum.any?(sections, &(&1.name == :workflow))
    end

    test "defines transformers in correct order" do
      transformers = AshJobs.transformers()

      # Extract transformer module names
      transformer_modules =
        Enum.map(transformers, fn
          {module, _opts} -> module
          module -> module
        end)

      # Verify order: GenerateErrorActions → IntegrateStateMachine → IntegrateOban
      generate_idx =
        Enum.find_index(
          transformer_modules,
          &(&1 == AshJobs.Transformers.GenerateErrorActions)
        )

      state_machine_idx =
        Enum.find_index(
          transformer_modules,
          &(&1 == AshJobs.Transformers.IntegrateStateMachine)
        )

      oban_idx =
        Enum.find_index(transformer_modules, &(&1 == AshJobs.Transformers.IntegrateOban))

      assert generate_idx < state_machine_idx
      assert state_machine_idx < oban_idx
    end

    test "defines verifiers" do
      verifiers = AshJobs.verifiers()
      assert AshJobs.Verifiers.ValidateWorkflow in verifiers
    end
  end

  # Skip extension compilation test for now - will enable when transformers/verifiers are implemented
  # describe "extension compilation" do
  #   test "can be used on a test resource" do
  #     defmodule TestResource do
  #       use Ash.Resource,
  #         extensions: [AshJobs, AshStateMachine, AshOban]
  #
  #       workflow do
  #         step :test_step do
  #           action :test_action
  #           on_success :completed
  #         end
  #       end
  #
  #       actions do
  #         defaults [:read]
  #
  #         update :test_action do
  #           accept []
  #         end
  #       end
  #     end
  #
  #     # Verify resource compiles without errors
  #     assert Code.ensure_loaded?(TestResource)
  #   end
  # end
end
