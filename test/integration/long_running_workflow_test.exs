defmodule AshJobs.Integration.LongRunningWorkflowTest do
  @moduledoc """
  Comprehensive tests for LongRunningWorkflow.

  LongRunningWorkflow demonstrates custom step options:
  - Custom queue names
  - Custom timeouts
  - Custom retry policies

  All steps auto-trigger (no manual steps).
  """

  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.TestResources.LongRunningWorkflow

  setup do
    TestRepo.delete_all(LongRunningWorkflow)

    :ok
  end

  describe "happy path" do
    test "workflow completes successfully through all steps" do
      {:ok, job} = LongRunningWorkflow.create(%{name: "happy-path"})
      assert job.state == :quick_step

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :quick_step)
      end)

      job = LongRunningWorkflow.get_by_id!(job.id)
      assert job.state == :completed
      assert job.quick_data == "quick_done"
      assert job.slow_data == "slow_done"
      assert job.retry_data == "retry_done"
    end

    test "each step processes correctly" do
      {:ok, job} = LongRunningWorkflow.create(%{name: "step-by-step"})

      {:ok, job} = LongRunningWorkflow.process_quick(job)
      assert job.state == :slow_step
      assert job.quick_data == "quick_done"

      {:ok, job} = LongRunningWorkflow.process_slow(job)
      assert job.state == :retry_step
      assert job.slow_data == "slow_done"

      {:ok, job} = LongRunningWorkflow.process_retry(job)
      assert job.state == :completed
      assert job.retry_data == "retry_done"
    end
  end

  describe "state transitions" do
    test "quick_step -> slow_step -> retry_step -> completed" do
      {:ok, job} = LongRunningWorkflow.create(%{name: "transitions"})
      assert job.state == :quick_step

      {:ok, job} = LongRunningWorkflow.process_quick(job)
      assert job.state == :slow_step

      {:ok, job} = LongRunningWorkflow.process_slow(job)
      assert job.state == :retry_step

      {:ok, job} = LongRunningWorkflow.process_retry(job)
      assert job.state == :completed
    end

    test "initial state is quick_step" do
      {:ok, job} = LongRunningWorkflow.create(%{name: "initial"})
      assert job.state == :quick_step
    end
  end

  describe "step configuration" do
    test "steps have correct queue configuration" do
      workflow = AshJobs.Info.workflow!(LongRunningWorkflow)

      quick_step = Enum.find(workflow.steps, &(&1.name == :quick_step))
      slow_step = Enum.find(workflow.steps, &(&1.name == :slow_step))
      retry_step = Enum.find(workflow.steps, &(&1.name == :retry_step))

      assert quick_step.queue == :fast_queue
      assert slow_step.queue == :slow_queue
      assert retry_step.queue == :retry_queue
    end

    test "steps have correct timeout configuration" do
      workflow = AshJobs.Info.workflow!(LongRunningWorkflow)

      quick_step = Enum.find(workflow.steps, &(&1.name == :quick_step))
      slow_step = Enum.find(workflow.steps, &(&1.name == :slow_step))

      assert quick_step.timeout_seconds == 30
      assert slow_step.timeout_seconds == 300
    end

    test "retry_step has correct retry configuration" do
      workflow = AshJobs.Info.workflow!(LongRunningWorkflow)

      retry_step = Enum.find(workflow.steps, &(&1.name == :retry_step))

      assert retry_step.retry_attempts == 5
      assert retry_step.retry_delay_seconds == 10
    end

    test "all steps auto-trigger (no manual steps)" do
      workflow = AshJobs.Info.workflow!(LongRunningWorkflow)

      for step <- workflow.steps do
        assert step.trigger == true, "Step #{step.name} should auto-trigger"
      end
    end
  end

  describe "Oban integration" do
    test "workers exist for all steps" do
      assert Code.ensure_loaded?(LongRunningWorkflow.AshOban.Worker.QuickStep)
      assert Code.ensure_loaded?(LongRunningWorkflow.AshOban.Worker.SlowStep)
      assert Code.ensure_loaded?(LongRunningWorkflow.AshOban.Worker.RetryStep)
    end

    test "schedulers exist for all steps" do
      assert Code.ensure_loaded?(LongRunningWorkflow.AshOban.Scheduler.QuickStep)
      assert Code.ensure_loaded?(LongRunningWorkflow.AshOban.Scheduler.SlowStep)
      assert Code.ensure_loaded?(LongRunningWorkflow.AshOban.Scheduler.RetryStep)
    end
  end

  describe "automatic job queuing" do
    test "workflow auto-completes in inline mode" do
      {:ok, job} = LongRunningWorkflow.create(%{name: "auto-complete"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :quick_step)
      end)

      job = LongRunningWorkflow.get_by_id!(job.id)
      assert job.state == :completed
    end
  end

  describe "data persistence" do
    test "all step data is persisted correctly" do
      {:ok, job} = LongRunningWorkflow.create(%{name: "persistence"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :quick_step)
      end)

      job = LongRunningWorkflow.get_by_id!(job.id)

      assert job.name == "persistence"
      assert job.quick_data == "quick_done"
      assert job.slow_data == "slow_done"
      assert job.retry_data == "retry_done"
      assert job.state == :completed
    end
  end
end
