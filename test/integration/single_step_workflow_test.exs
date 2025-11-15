defmodule AshJobs.Integration.SingleStepWorkflowTest do
  @moduledoc """
  Comprehensive tests for SingleStepWorkflow.

  SingleStepWorkflow is an edge case - a workflow with only one step.
  Tests verify it completes in a single execution.
  """

  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.TestResources.SingleStepWorkflow

  setup do
    TestRepo.delete_all(SingleStepWorkflow)

    :ok
  end

  describe "happy path" do
    test "single step workflow completes in one execution" do
      {:ok, job} = SingleStepWorkflow.create(%{name: "one-step"})
      assert job.state == :only_step

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :only_step)
      end)

      job = SingleStepWorkflow.get_by_id!(job.id)
      assert job.state == :completed
      assert job.result == "done"
    end

    test "action can be called directly" do
      {:ok, job} = SingleStepWorkflow.create(%{name: "direct-call"})
      assert job.state == :only_step

      {:ok, job} = SingleStepWorkflow.process(job)

      assert job.state == :completed
      assert job.result == "done"
    end
  end

  describe "state transitions" do
    test "transitions directly from only_step to completed" do
      {:ok, job} = SingleStepWorkflow.create(%{name: "transition"})
      assert job.state == :only_step

      {:ok, job} = SingleStepWorkflow.process(job)

      assert job.state == :completed
      assert job.result == "done"
    end

    test "initial state is only_step" do
      {:ok, job} = SingleStepWorkflow.create(%{name: "initial"})
      assert job.state == :only_step
    end

    test "terminal state is completed" do
      {:ok, job} = SingleStepWorkflow.create(%{name: "terminal"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :only_step)
      end)

      job = SingleStepWorkflow.get_by_id!(job.id)
      assert job.state == :completed

      terminal_steps = AshJobs.Info.terminal_steps(SingleStepWorkflow)
      assert length(terminal_steps) == 1
    end
  end

  describe "workflow configuration" do
    test "has exactly one step" do
      workflow = AshJobs.Info.workflow!(SingleStepWorkflow)

      assert length(workflow.steps) == 1

      [step] = workflow.steps
      assert step.name == :only_step
      assert step.action == :process
      assert step.on_success == :completed
    end

    test "step is both entry point and terminal" do
      entry_points = AshJobs.Info.entry_points(SingleStepWorkflow)
      terminal_steps = AshJobs.Info.terminal_steps(SingleStepWorkflow)

      assert length(entry_points) == 1
      assert length(terminal_steps) == 1
      assert hd(entry_points).name == :only_step
      assert hd(terminal_steps).name == :only_step
    end

    test "step auto-triggers" do
      workflow = AshJobs.Info.workflow!(SingleStepWorkflow)
      [step] = workflow.steps

      assert step.trigger == true
    end
  end

  describe "Oban integration" do
    test "worker exists for the step" do
      assert Code.ensure_loaded?(SingleStepWorkflow.AshOban.Worker.OnlyStep)
    end

    test "scheduler exists for the step" do
      assert Code.ensure_loaded?(SingleStepWorkflow.AshOban.Scheduler.OnlyStep)
    end
  end

  describe "data persistence" do
    test "result is persisted correctly" do
      {:ok, job} = SingleStepWorkflow.create(%{name: "persistence"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :only_step)
      end)

      job = SingleStepWorkflow.get_by_id!(job.id)

      assert job.name == "persistence"
      assert job.result == "done"
      assert job.state == :completed
    end
  end
end
