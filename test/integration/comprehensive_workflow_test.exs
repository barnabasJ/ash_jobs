defmodule AshJobs.Integration.ComprehensiveWorkflowTest do
  @moduledoc """
  Integration tests for workflow execution covering error handling, manual steps,
  step options, edge cases, and concurrency.
  """

  use ExUnit.Case, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.TestRepo

  alias AshJobs.TestResources.{
    SimpleWorkflow,
    BranchingWorkflow,
    ManualWorkflow,
    LongRunningWorkflow,
    SingleStepWorkflow,
    MultiTerminalWorkflow,
    CustomStateWorkflow
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, {:shared, self()})

    TestRepo.delete_all(SimpleWorkflow)
    TestRepo.delete_all(BranchingWorkflow)
    TestRepo.delete_all(ManualWorkflow)
    TestRepo.delete_all(LongRunningWorkflow)
    TestRepo.delete_all(SingleStepWorkflow)
    TestRepo.delete_all(MultiTerminalWorkflow)
    TestRepo.delete_all(CustomStateWorkflow)

    :ok
  end

  describe "SimpleWorkflow - basic functionality" do
    test "executes simple two-step workflow" do
      {:ok, job} = SimpleWorkflow.create(%{name: "simple-001"})
      assert job.state == :process
      assert job.result == nil

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :process)
      end)

      job = TestRepo.get!(SimpleWorkflow, job.id)
      assert job.state == :completed
      assert job.result == "processed"
    end

    test "multiple simple workflows run independently" do
      {:ok, job1} = SimpleWorkflow.create(%{name: "simple-002"})
      {:ok, job2} = SimpleWorkflow.create(%{name: "simple-003"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job1, :process)
        AshOban.run_trigger(job2, :process)
      end)

      job1 = TestRepo.get!(SimpleWorkflow, job1.id)
      job2 = TestRepo.get!(SimpleWorkflow, job2.id)

      assert job1.state == :completed
      assert job2.state == :completed
      assert job1.id != job2.id
    end
  end

  describe "SingleStepWorkflow - edge case" do
    test "single step workflow completes in one execution" do
      {:ok, job} = SingleStepWorkflow.create(%{name: "single-001"})
      assert job.state == :only_step

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :only_step)
      end)

      job = TestRepo.get!(SingleStepWorkflow, job.id)
      assert job.state == :completed
      assert job.result == "done"
    end
  end

  describe "BranchingWorkflow - error handling" do
    test "happy path - all steps succeed" do
      {:ok, job} = BranchingWorkflow.create(%{name: "branch-001", force_error_at: nil})
      assert job.state == :start

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :start)
        job = TestRepo.get!(BranchingWorkflow, job.id)
        AshOban.run_trigger(job, :step_one)
        job = TestRepo.get!(BranchingWorkflow, job.id)
        AshOban.run_trigger(job, :step_two)
      end)

      job = TestRepo.get!(BranchingWorkflow, job.id)
      assert job.state == :completed
      assert job.step_one_data == "processed"
      assert job.step_two_data == "completed"
      assert job.error_message == nil
    end

    test "error at start step routes to handle_start_error" do
      {:ok, job} = BranchingWorkflow.create(%{name: "branch-002", force_error_at: "start"})
      assert job.state == :start

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :start)
      end)

      job = TestRepo.get!(BranchingWorkflow, job.id)
      assert job.state == :failed
      assert job.error_message != nil
    end

    test "error at step_one routes to handle_step_one_error" do
      {:ok, job} = BranchingWorkflow.create(%{name: "branch-003", force_error_at: "step_one"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :start)
        job = TestRepo.get!(BranchingWorkflow, job.id)
        AshOban.run_trigger(job, :step_one)
      end)

      job = TestRepo.get!(BranchingWorkflow, job.id)
      assert job.state == :failed
      assert job.error_message != nil
    end

    test "error at step_two routes to handle_step_two_error" do
      {:ok, job} = BranchingWorkflow.create(%{name: "branch-004", force_error_at: "step_two"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :start)
        job = TestRepo.get!(BranchingWorkflow, job.id)
        AshOban.run_trigger(job, :step_one)
        job = TestRepo.get!(BranchingWorkflow, job.id)
        AshOban.run_trigger(job, :step_two)
      end)

      job = TestRepo.get!(BranchingWorkflow, job.id)
      assert job.state == :failed
      assert job.error_message != nil
    end

    test "error handlers can be called directly" do
      {:ok, job} = BranchingWorkflow.create(%{name: "branch-005", force_error_at: nil})

      {:ok, job} = BranchingWorkflow.notify_start_error(job, %{error: %{message: "Manual error"}})

      assert job.state == :failed
      assert job.error_message == "Manual error"
    end
  end

  describe "ManualWorkflow - manual step execution" do
    test "auto step triggers automatically, manual step requires explicit call" do
      {:ok, job} = ManualWorkflow.create(%{name: "manual-001"})
      assert job.state == :auto_step

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :auto_step)
      end)

      job = TestRepo.get!(ManualWorkflow, job.id)
      assert job.state == :manual_step
      assert job.auto_data == "auto_processed"
      assert job.manual_data == nil

      {:ok, job} = ManualWorkflow.process_manual(job)

      assert job.state == :completed
      assert job.manual_data == "manual_processed"
    end

    test "manual step does not schedule Oban job" do
      {:ok, job} = ManualWorkflow.create(%{name: "manual-002"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :auto_step)
      end)

      job = TestRepo.get!(ManualWorkflow, job.id)
      assert job.state == :manual_step, "Manual step should not auto-execute"
    end
  end

  describe "LongRunningWorkflow - step options" do
    test "workflow with step options executes through all queues" do
      {:ok, job} = LongRunningWorkflow.create(%{name: "long-001"})
      assert job.state == :quick_step

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :quick_step)
        job = TestRepo.get!(LongRunningWorkflow, job.id)
        AshOban.run_trigger(job, :slow_step)
        job = TestRepo.get!(LongRunningWorkflow, job.id)
        AshOban.run_trigger(job, :retry_step)
      end)

      job = TestRepo.get!(LongRunningWorkflow, job.id)
      assert job.state == :completed
      assert job.quick_data == "quick_done"
      assert job.slow_data == "slow_done"
      assert job.retry_data == "retry_done"
    end

    test "step configuration is present in step definitions" do
      steps = AshJobs.Info.steps(LongRunningWorkflow)

      quick_step = Enum.find(steps, &(&1.name == :quick_step))
      assert quick_step.queue == :fast_queue
      assert quick_step.timeout_seconds == 30

      slow_step = Enum.find(steps, &(&1.name == :slow_step))
      assert slow_step.queue == :slow_queue
      assert slow_step.timeout_seconds == 300

      retry_step = Enum.find(steps, &(&1.name == :retry_step))
      assert retry_step.queue == :retry_queue
      assert retry_step.retry_attempts == 5
      assert retry_step.retry_delay_seconds == 10
    end
  end

  describe "MultiTerminalWorkflow - multiple terminal states" do
    test "happy path completes in completed state" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "multi-001"})
      assert job.state == :start

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :start)
        job = TestRepo.get!(MultiTerminalWorkflow, job.id)
        AshOban.run_trigger(job, :process)
      end)

      job = TestRepo.get!(MultiTerminalWorkflow, job.id)
      assert job.state == :completed
      assert job.result == "work_done"
    end

    test "manual cancellation ends in cancelled state" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "multi-002"})

      {:ok, job} = MultiTerminalWorkflow.do_cancel(job, %{cancellation_reason: "User requested"})

      assert job.state == :cancelled
      assert job.cancellation_reason == "User requested"
    end

    test "workflow has multiple terminal states configured" do
      terminal_steps = AshJobs.Info.terminal_steps(MultiTerminalWorkflow)
      terminal_step_names = Enum.map(terminal_steps, & &1.name)

      assert :process in terminal_step_names or :start in terminal_step_names
      assert :handle_error in terminal_step_names
      assert :cancel in terminal_step_names
    end
  end

  describe "CustomStateWorkflow - custom configuration" do
    test "uses custom state attribute name" do
      {:ok, job} = CustomStateWorkflow.create(%{name: "custom-001"})

      assert job.status == :initialize
      refute Map.has_key?(job, :state)

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :initialize)
        job = TestRepo.get!(CustomStateWorkflow, job.id)
        AshOban.run_trigger(job, :process)
      end)

      job = TestRepo.get!(CustomStateWorkflow, job.id)
      assert job.status == :completed
      assert job.result == "custom_done"
    end

    test "workflow info respects custom state attribute" do
      {:ok, workflow} = AshJobs.Info.workflow(CustomStateWorkflow)
      assert workflow.state_attribute == :status
    end
  end

  describe "AshJobs.Info introspection across workflows" do
    test "SimpleWorkflow info" do
      steps = AshJobs.Info.steps(SimpleWorkflow)
      assert length(steps) == 1

      entry_points = AshJobs.Info.entry_points(SimpleWorkflow)
      assert length(entry_points) == 1
      assert List.first(entry_points).name == :process
    end

    test "BranchingWorkflow info" do
      steps = AshJobs.Info.steps(BranchingWorkflow)
      # 3 main + 3 error handlers
      assert length(steps) == 6

      entry_points = AshJobs.Info.entry_points(BranchingWorkflow)
      assert length(entry_points) == 1
      assert List.first(entry_points).name == :start

      terminal_steps = AshJobs.Info.terminal_steps(BranchingWorkflow)
      # All error handlers and final step are terminal
      assert length(terminal_steps) >= 3
    end

    test "ManualWorkflow info identifies manual steps" do
      steps = AshJobs.Info.steps(ManualWorkflow)

      auto_step = Enum.find(steps, &(&1.name == :auto_step))
      manual_step = Enum.find(steps, &(&1.name == :manual_step))

      assert auto_step.trigger == true
      assert manual_step.trigger == false
    end
  end

  describe "concurrency and isolation" do
    test "multiple workflows of different types run concurrently" do
      {:ok, simple} = SimpleWorkflow.create(%{name: "concurrent-simple"})
      {:ok, single} = SingleStepWorkflow.create(%{name: "concurrent-single"})
      {:ok, branch} = BranchingWorkflow.create(%{name: "concurrent-branch", force_error_at: nil})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(simple, :process)
        AshOban.run_trigger(single, :only_step)

        AshOban.run_trigger(branch, :start)
        branch = TestRepo.get!(BranchingWorkflow, branch.id)
        AshOban.run_trigger(branch, :step_one)
        branch = TestRepo.get!(BranchingWorkflow, branch.id)
        AshOban.run_trigger(branch, :step_two)
      end)

      simple = TestRepo.get!(SimpleWorkflow, simple.id)
      single = TestRepo.get!(SingleStepWorkflow, single.id)
      branch = TestRepo.get!(BranchingWorkflow, branch.id)

      assert simple.state == :completed
      assert single.state == :completed
      assert branch.state == :completed
    end

    test "same workflow type with multiple instances maintains isolation" do
      jobs =
        for i <- 1..5 do
          {:ok, job} = SimpleWorkflow.create(%{name: "isolation-#{i}"})
          job
        end

      Oban.Testing.with_testing_mode(:inline, fn ->
        Enum.each(jobs, fn job ->
          AshOban.run_trigger(job, :process)
        end)
      end)

      reloaded_jobs = Enum.map(jobs, &TestRepo.get!(SimpleWorkflow, &1.id))

      assert Enum.all?(reloaded_jobs, &(&1.state == :completed))
      assert Enum.all?(reloaded_jobs, &(&1.result == "processed"))

      ids = Enum.map(reloaded_jobs, & &1.id)
      assert length(Enum.uniq(ids)) == 5
    end
  end

  describe "error edge cases" do
    test "calling non-error-handler action on error handler step" do
      {:ok, job} = BranchingWorkflow.create(%{name: "edge-001", force_error_at: nil})

      # Try to manually call an error handler with different error formats
      {:ok, job} = BranchingWorkflow.notify_start_error(job, %{error: "string error"})
      assert job.error_message == "string error"

      {:ok, job} = BranchingWorkflow.notify_step_one_error(job, %{error: %{message: "map error"}})
      assert job.error_message == "map error"

      {:ok, job} = BranchingWorkflow.notify_step_two_error(job, %{error: nil})
      assert job.error_message == "Error at step_two"
    end
  end

  describe "state machine validation" do
    test "workflow actions properly transition state" do
      {:ok, job} = SimpleWorkflow.create(%{name: "validation-002"})
      assert job.state == :process

      {:ok, job} = SimpleWorkflow.do_work(job)

      assert job.state == :completed
    end
  end

  describe "workflow with generated actions" do
    test "error handler actions are generated automatically" do
      actions = Ash.Resource.Info.actions(BranchingWorkflow)
      action_names = Enum.map(actions, & &1.name)

      # Error handler actions should exist
      assert :notify_start_error in action_names
      assert :notify_step_one_error in action_names
      assert :notify_step_two_error in action_names

      # All error handlers should have error argument
      for error_action_name <- [
            :notify_start_error,
            :notify_step_one_error,
            :notify_step_two_error
          ] do
        action = Enum.find(actions, &(&1.name == error_action_name))
        assert action
        error_arg = Enum.find(action.arguments, &(&1.name == :error))
        assert error_arg
      end
    end
  end

  describe "Oban worker and scheduler generation" do
    test "workers and schedulers exist for all triggered steps" do
      assert Code.ensure_loaded?(SimpleWorkflow.AshOban.Worker.Process)
      assert Code.ensure_loaded?(SimpleWorkflow.AshOban.Scheduler.Process)

      assert Code.ensure_loaded?(ManualWorkflow.AshOban.Worker.AutoStep)
      refute Code.ensure_loaded?(ManualWorkflow.AshOban.Worker.ManualStep)
    end

    test "different queues result in jobs in different queues" do
      {:ok, job} = LongRunningWorkflow.create(%{name: "queue-test"})

      fast_jobs = all_enqueued(queue: :fast_queue)
      assert length(fast_jobs) > 0

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :quick_step)
        job = TestRepo.get!(LongRunningWorkflow, job.id)
        assert job.state == :slow_step

        AshOban.run_trigger(job, :slow_step)
        job = TestRepo.get!(LongRunningWorkflow, job.id)
        assert job.state == :retry_step
      end)
    end
  end
end
