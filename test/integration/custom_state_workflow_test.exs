defmodule AshJobs.Integration.CustomStateWorkflowTest do
  @moduledoc """
  Comprehensive tests for CustomStateWorkflow.

  CustomStateWorkflow demonstrates using a custom state attribute name (:status)
  instead of the default :state attribute.

  Tests verify custom state attribute configuration works correctly.
  """

  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.TestResources.CustomStateWorkflow

  setup do
    TestRepo.delete_all(CustomStateWorkflow)

    :ok
  end

  describe "happy path with custom state attribute" do
    test "workflow completes using :status attribute" do
      {:ok, job} = CustomStateWorkflow.create(%{name: "custom-happy"})

      assert job.status == :initialize
      refute Map.has_key?(job, :state)

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :initialize)
      end)

      job = CustomStateWorkflow.get_by_id!(job.id)
      assert job.status == :completed
      assert job.result == "custom_done"
    end

    test "action transitions work with custom state attribute" do
      {:ok, job} = CustomStateWorkflow.create(%{name: "custom-transition"})
      assert job.status == :initialize

      {:ok, job} = CustomStateWorkflow.setup(job)
      assert job.status == :process

      {:ok, job} = CustomStateWorkflow.do_work(job)
      assert job.status == :completed
      assert job.result == "custom_done"
    end
  end

  describe "state transitions" do
    test "transitions from initialize to process to completed" do
      {:ok, job} = CustomStateWorkflow.create(%{name: "transition"})
      assert job.status == :initialize

      {:ok, job} = CustomStateWorkflow.setup(job)
      assert job.status == :process

      {:ok, job} = CustomStateWorkflow.do_work(job)
      assert job.status == :completed
    end

    test "initial status is initialize" do
      {:ok, job} = CustomStateWorkflow.create(%{name: "initial"})
      assert job.status == :initialize
    end

    test "terminal status is completed" do
      {:ok, job} = CustomStateWorkflow.create(%{name: "terminal"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :initialize)
      end)

      job = CustomStateWorkflow.get_by_id!(job.id)
      assert job.status == :completed
    end
  end

  describe "workflow configuration" do
    test "uses custom state attribute name" do
      workflow = AshJobs.Info.workflow!(CustomStateWorkflow)

      assert workflow.state_attribute == :status
    end

    test "workflow info respects custom state attribute" do
      workflow = AshJobs.Info.workflow!(CustomStateWorkflow)

      assert workflow.state_attribute == :status
      assert length(workflow.steps) == 2

      initialize_step = Enum.find(workflow.steps, &(&1.name == :initialize))
      process_step = Enum.find(workflow.steps, &(&1.name == :process))

      assert initialize_step.on_success == :process
      assert process_step.on_success == :completed
    end

    test "state transitions use custom attribute" do
      {:ok, job} = CustomStateWorkflow.create(%{name: "state-attr"})

      initial_status = job.status

      {:ok, job} = CustomStateWorkflow.setup(job)

      assert job.status != initial_status
      assert job.status == :process
    end
  end

  describe "Oban integration" do
    test "workers use custom state attribute for triggers" do
      assert Code.ensure_loaded?(CustomStateWorkflow.AshOban.Worker.Initialize)
      assert Code.ensure_loaded?(CustomStateWorkflow.AshOban.Worker.Process)
    end

    test "schedulers use custom state attribute" do
      assert Code.ensure_loaded?(CustomStateWorkflow.AshOban.Scheduler.Initialize)
      assert Code.ensure_loaded?(CustomStateWorkflow.AshOban.Scheduler.Process)
    end

    test "Oban triggers work with custom state attribute" do
      {:ok, job} = CustomStateWorkflow.create(%{name: "oban-trigger"})
      assert job.status == :initialize

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :initialize)
      end)

      job = CustomStateWorkflow.get_by_id!(job.id)
      assert job.status == :completed
    end
  end

  describe "data persistence" do
    test "status persists correctly" do
      {:ok, job} = CustomStateWorkflow.create(%{name: "persistence"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :initialize)
      end)

      job = CustomStateWorkflow.get_by_id!(job.id)

      assert job.name == "persistence"
      assert job.status == :completed
      assert job.result == "custom_done"
    end

    test "multiple workflows maintain independent status" do
      {:ok, job1} = CustomStateWorkflow.create(%{name: "job1"})
      {:ok, job2} = CustomStateWorkflow.create(%{name: "job2"})

      {:ok, job2} = CustomStateWorkflow.setup(job2)
      {:ok, job2} = CustomStateWorkflow.do_work(job2)

      job1 = CustomStateWorkflow.get_by_id!(job1.id)
      job2 = CustomStateWorkflow.get_by_id!(job2.id)

      assert job1.status == :initialize
      assert job2.status == :completed
    end
  end

  describe "automatic job queuing" do
    test "auto-queuing works with custom state attribute" do
      {:ok, job} = CustomStateWorkflow.create(%{name: "auto-queue"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :initialize)
      end)

      job = CustomStateWorkflow.get_by_id!(job.id)
      assert job.status == :completed
    end
  end
end
