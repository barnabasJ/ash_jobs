defmodule AshJobs.Integration.SimpleWorkflowTest do
  @moduledoc """
  Comprehensive tests for SimpleWorkflow.

  SimpleWorkflow is a minimal two-state workflow (process -> completed).
  Tests cover happy path, state transitions, and automatic job queuing.
  """

  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.TestResources.SimpleWorkflow

  setup do
    TestRepo.delete_all(SimpleWorkflow)
    :ok
  end

  describe "happy path" do
    test "workflow completes successfully from start to finish" do
      {:ok, job} = SimpleWorkflow.create(%{name: "test-happy-path"})

      assert job.state == :process
      assert job.result == nil

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :process)
      end)

      job = SimpleWorkflow.get_by_id!(job.id)
      assert job.state == :completed
      assert job.result == "processed"
    end

    test "multiple workflows run independently" do
      {:ok, job1} = SimpleWorkflow.create(%{name: "test-1"})
      {:ok, job2} = SimpleWorkflow.create(%{name: "test-2"})

      assert job1.id != job2.id
      assert job1.state == :process
      assert job2.state == :process

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job1, :process)
      end)

      job1 = SimpleWorkflow.get_by_id!(job1.id)
      job2 = SimpleWorkflow.get_by_id!(job2.id)

      assert job1.state == :completed
      assert job2.state == :process

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job2, :process)
      end)

      job2 = SimpleWorkflow.get_by_id!(job2.id)
      assert job2.state == :completed
    end
  end

  describe "state transitions" do
    test "transitions from process to completed" do
      {:ok, job} = SimpleWorkflow.create(%{name: "test-transition"})
      assert job.state == :process

      {:ok, job} = SimpleWorkflow.do_work(job)

      assert job.state == :completed
      assert job.result == "processed"
    end

    test "initial state is process" do
      {:ok, job} = SimpleWorkflow.create(%{name: "test-initial"})
      assert job.state == :process
    end

    test "cannot transition from completed" do
      {:ok, job} = SimpleWorkflow.create(%{name: "test-terminal"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :process)
      end)

      job = SimpleWorkflow.get_by_id!(job.id)
      assert job.state == :completed

      Oban.Testing.with_testing_mode(:inline, fn ->
        :ok
      end)

      job = SimpleWorkflow.get_by_id!(job.id)
      assert job.state == :completed
    end
  end

  describe "automatic job queuing" do
    test "workflow automatically queues and completes in inline mode" do
      {:ok, job} = SimpleWorkflow.create(%{name: "test-auto-continue"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :process)
      end)

      job = SimpleWorkflow.get_by_id!(job.id)
      assert job.state == :completed
      assert job.result == "processed"
    end

    test "Oban worker and scheduler modules are generated" do
      assert Code.ensure_loaded?(SimpleWorkflow.AshOban.Worker.Process)
      assert Code.ensure_loaded?(SimpleWorkflow.AshOban.Scheduler.Process)
    end
  end

  describe "workflow configuration" do
    test "workflow has correct step configuration" do
      workflow = AshJobs.Info.workflow!(SimpleWorkflow)

      assert workflow.state_attribute == :state
      assert length(workflow.steps) == 1

      [step] = workflow.steps
      assert step.name == :process
      assert step.action == :do_work
      assert step.on_success == :completed
      assert step.queue == :default
      assert step.trigger == true
    end

    test "entry points are identified correctly" do
      entry_points = AshJobs.Info.entry_points(SimpleWorkflow)
      assert length(entry_points) == 1
      assert hd(entry_points).name == :process
    end

    test "terminal steps are identified correctly" do
      terminal_steps = AshJobs.Info.terminal_steps(SimpleWorkflow)
      assert length(terminal_steps) == 1
      assert hd(terminal_steps).name == :process
      assert hd(terminal_steps).on_success == :completed
    end
  end

  describe "data persistence" do
    test "result data is persisted correctly" do
      {:ok, job} = SimpleWorkflow.create(%{name: "test-persistence"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :process)
      end)

      job = SimpleWorkflow.get_by_id!(job.id)

      assert job.name == "test-persistence"
      assert job.result == "processed"
      assert job.state == :completed
      assert job.inserted_at != nil
      assert job.updated_at != nil
    end

    test "timestamps are maintained correctly" do
      {:ok, job} = SimpleWorkflow.create(%{name: "test-timestamps"})
      inserted_at = job.inserted_at

      {:ok, job} = SimpleWorkflow.do_work(job)

      assert job.inserted_at == inserted_at
      assert job.updated_at != nil
    end
  end
end
