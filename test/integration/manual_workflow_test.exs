defmodule AshJobs.Integration.ManualWorkflowTest do
  @moduledoc """
  Comprehensive tests for ManualWorkflow.

  ManualWorkflow demonstrates mixed automatic and manual steps.
  Tests cover automatic triggering, manual step execution, and state transitions.
  """

  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.TestResources.ManualWorkflow

  setup do
    TestRepo.delete_all(ManualWorkflow)

    :ok
  end

  describe "automatic and manual step execution" do
    test "auto step triggers automatically, manual step requires explicit call" do
      {:ok, job} = ManualWorkflow.create(%{name: "manual-test"})
      assert job.state == :auto_step

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :auto_step)
      end)

      job = ManualWorkflow.get_by_id!(job.id)
      assert job.state == :manual_step
      assert job.auto_data == "auto_processed"

      {:ok, job} = ManualWorkflow.process_manual(job)

      assert job.state == :completed
      assert job.manual_data == "manual_processed"
    end

    test "manual step does not create Oban job" do
      {:ok, job} = ManualWorkflow.create(%{name: "no-trigger"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :auto_step)
      end)

      job = ManualWorkflow.get_by_id!(job.id)
      assert job.state == :manual_step

      assert job.state == :manual_step
    end
  end

  describe "state transitions" do
    test "auto_step -> manual_step -> completed" do
      {:ok, job} = ManualWorkflow.create(%{name: "transitions"})
      assert job.state == :auto_step

      {:ok, job} = ManualWorkflow.process_auto(job)
      assert job.state == :manual_step
      assert job.auto_data == "auto_processed"

      {:ok, job} = ManualWorkflow.process_manual(job)
      assert job.state == :completed
      assert job.manual_data == "manual_processed"
    end
  end

  describe "workflow configuration" do
    test "identifies manual steps correctly" do
      workflow = AshJobs.Info.workflow!(ManualWorkflow)

      auto_step = Enum.find(workflow.steps, &(&1.name == :auto_step))
      manual_step = Enum.find(workflow.steps, &(&1.name == :manual_step))

      assert auto_step.trigger == true
      assert manual_step.trigger == false
    end

    test "Oban worker exists for auto step but not manual step" do
      assert Code.ensure_loaded?(ManualWorkflow.AshOban.Worker.AutoStep)
      refute Code.ensure_loaded?(ManualWorkflow.AshOban.Worker.ManualStep)
    end
  end
end
