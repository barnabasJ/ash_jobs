defmodule AshJobs.Integration.MultiTerminalWorkflowTest do
  @moduledoc """
  Comprehensive tests for MultiTerminalWorkflow.

  MultiTerminalWorkflow demonstrates multiple terminal states:
  - completed (happy path)
  - failed (error path)
  - cancelled (manual cancellation via trigger: false step)

  Tests verify workflows can end in different states.
  """

  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.TestResources.MultiTerminalWorkflow

  setup do
    TestRepo.delete_all(MultiTerminalWorkflow)

    :ok
  end

  describe "happy path - completed state" do
    test "workflow completes successfully" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "happy-path"})
      assert job.state == :start

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :start)
      end)

      job = MultiTerminalWorkflow.get_by_id!(job.id)
      assert job.state == :completed
      assert job.result == "work_done"
    end

    test "completes through all steps manually" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "manual-steps"})
      assert job.state == :start

      {:ok, job} = MultiTerminalWorkflow.begin(job)
      assert job.state == :process

      {:ok, job} = MultiTerminalWorkflow.do_work(job)
      assert job.state == :completed
      assert job.result == "work_done"
    end
  end

  describe "error path - failed state" do
    test "error handler routes to failed state" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "error-handler"})

      {:ok, job} = MultiTerminalWorkflow.notify_error(job, %{error: %{message: "Test error"}})

      assert job.state == :failed
      assert job.error_message == "Test error"
    end

    test "error handler with string error" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "string-error"})

      {:ok, job} = MultiTerminalWorkflow.notify_error(job, %{error: %{}})

      assert job.state == :failed
      assert job.error_message == "Unknown error"
    end
  end

  describe "cancellation path - cancelled state" do
    test "manual cancellation ends in cancelled state" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "cancel"})
      assert job.state == :start

      {:ok, job} = MultiTerminalWorkflow.do_cancel(job)

      assert job.state == :cancelled
      assert job.cancellation_reason == "User cancelled"
    end

    test "can cancel with custom reason" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "cancel-reason"})

      {:ok, job} = MultiTerminalWorkflow.do_cancel(job, %{cancellation_reason: "Timeout"})

      assert job.state == :cancelled
      assert job.cancellation_reason == "Timeout"
    end

    test "can cancel from any state" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "cancel-anytime"})

      {:ok, job} = MultiTerminalWorkflow.begin(job)
      assert job.state == :process

      {:ok, job} = MultiTerminalWorkflow.do_cancel(job)

      assert job.state == :cancelled
    end
  end

  describe "state transitions" do
    test "start -> process -> completed transition" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "transition-complete"})
      assert job.state == :start

      {:ok, job} = MultiTerminalWorkflow.begin(job)
      assert job.state == :process

      {:ok, job} = MultiTerminalWorkflow.do_work(job)
      assert job.state == :completed
    end

    test "any state -> failed transition via error handler" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "transition-fail"})
      assert job.state == :start

      {:ok, job} = MultiTerminalWorkflow.notify_error(job, %{error: %{message: "Error"}})
      assert job.state == :failed
    end

    test "any state -> cancelled transition" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "transition-cancel"})
      assert job.state == :start

      {:ok, job} = MultiTerminalWorkflow.do_cancel(job)
      assert job.state == :cancelled
    end
  end

  describe "workflow configuration" do
    test "has multiple terminal states configured" do
      workflow = AshJobs.Info.workflow!(MultiTerminalWorkflow)

      terminal_states =
        workflow.steps
        |> Enum.flat_map(fn step ->
          [step.on_success, step.on_complete]
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      assert :completed in terminal_states
      assert :failed in terminal_states
      assert :cancelled in terminal_states
    end

    test "cancel step has trigger: false" do
      workflow = AshJobs.Info.workflow!(MultiTerminalWorkflow)

      cancel_step = Enum.find(workflow.steps, &(&1.name == :cancel))

      assert cancel_step.trigger == false
    end

    test "identifies terminal steps" do
      terminal_steps = AshJobs.Info.terminal_steps(MultiTerminalWorkflow)

      terminal_step_names = Enum.map(terminal_steps, & &1.name)

      assert :process in terminal_step_names
      assert :handle_error in terminal_step_names
      assert :cancel in terminal_step_names
    end
  end

  describe "Oban integration" do
    test "workers exist for auto-trigger steps" do
      assert Code.ensure_loaded?(MultiTerminalWorkflow.AshOban.Worker.Start)
      assert Code.ensure_loaded?(MultiTerminalWorkflow.AshOban.Worker.Process)
    end

    test "cancel step has no worker (trigger: false)" do
      refute Code.ensure_loaded?(MultiTerminalWorkflow.AshOban.Worker.Cancel)
    end
  end

  describe "terminal state behavior" do
    test "completed is a terminal state" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "terminal-completed"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :start)
      end)

      job = MultiTerminalWorkflow.get_by_id!(job.id)
      assert job.state == :completed
    end

    test "failed is a terminal state" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "terminal-failed"})
      {:ok, job} = MultiTerminalWorkflow.notify_error(job, %{error: %{message: "Test"}})

      assert job.state == :failed
    end

    test "cancelled is a terminal state" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "terminal-cancelled"})
      {:ok, job} = MultiTerminalWorkflow.do_cancel(job)

      assert job.state == :cancelled
    end
  end

  describe "data persistence" do
    test "result data persists through completion" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "persistence"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :start)
      end)

      job = MultiTerminalWorkflow.get_by_id!(job.id)

      assert job.name == "persistence"
      assert job.result == "work_done"
      assert job.state == :completed
    end

    test "error message persists on failure" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "error-persistence"})

      {:ok, job} =
        MultiTerminalWorkflow.notify_error(job, %{error: %{message: "Persistent error"}})

      job = MultiTerminalWorkflow.get_by_id!(job.id)

      assert job.error_message == "Persistent error"
      assert job.state == :failed
    end

    test "cancellation reason persists" do
      {:ok, job} = MultiTerminalWorkflow.create(%{name: "cancel-persistence"})

      {:ok, job} =
        MultiTerminalWorkflow.do_cancel(job, %{cancellation_reason: "Persistent cancel"})

      job = MultiTerminalWorkflow.get_by_id!(job.id)

      assert job.cancellation_reason == "Persistent cancel"
      assert job.state == :cancelled
    end
  end
end
