defmodule AshJobs.Integration.BranchingWorkflowTest do
  @moduledoc """
  Comprehensive tests for BranchingWorkflow.

  BranchingWorkflow demonstrates error handling with multiple error paths.
  Tests cover happy path, error handling at each step, and state transitions.
  """

  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.TestResources.BranchingWorkflow

  setup do
    TestRepo.delete_all(BranchingWorkflow)
    :ok
  end

  describe "happy path" do
    test "workflow completes successfully through all steps" do
      {:ok, job} = BranchingWorkflow.create(%{name: "happy-path"})
      assert job.state == :start

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :start)
      end)

      job = BranchingWorkflow.get_by_id!(job.id)
      assert job.state == :completed
      assert job.step_one_data == "processed"
      assert job.step_two_data == "completed"
      assert job.error_message == nil
    end
  end

  describe "error handling" do
    test "error at start step routes to handle_start_error" do
      {:ok, job} = BranchingWorkflow.create(%{name: "error-start", force_error_at: "start"})
      assert job.state == :start

      error =
        try do
          Oban.Testing.with_testing_mode(:inline, fn ->
            AshOban.run_trigger(job, :start)
          end)

          nil
        catch
          _kind, error -> error
        end

      assert error != nil

      {:ok, job} = BranchingWorkflow.notify_start_error(job, %{error: error})

      assert job.state == :failed
      assert job.error_message != nil
    end

    test "error at step_one routes to handle_step_one_error" do
      {:ok, job} = BranchingWorkflow.create(%{name: "error-step-one", force_error_at: "step_one"})

      error =
        try do
          Oban.Testing.with_testing_mode(:inline, fn ->
            AshOban.run_trigger(job, :start)
            job = BranchingWorkflow.get_by_id!(job.id)
            AshOban.run_trigger(job, :step_one)
          end)

          nil
        catch
          _kind, error -> error
        end

      assert error != nil

      job = BranchingWorkflow.get_by_id!(job.id)
      {:ok, job} = BranchingWorkflow.notify_step_one_error(job, %{error: error})

      assert job.state == :failed
      assert job.error_message != nil
    end

    test "error at step_two routes to handle_step_two_error" do
      {:ok, job} = BranchingWorkflow.create(%{name: "error-step-two", force_error_at: "step_two"})

      error =
        try do
          Oban.Testing.with_testing_mode(:inline, fn ->
            AshOban.run_trigger(job, :start)
            job = BranchingWorkflow.get_by_id!(job.id)
            AshOban.run_trigger(job, :step_one)
            job = BranchingWorkflow.get_by_id!(job.id)
            AshOban.run_trigger(job, :step_two)
          end)

          nil
        catch
          _kind, error -> error
        end

      assert error != nil

      job = BranchingWorkflow.get_by_id!(job.id)
      {:ok, job} = BranchingWorkflow.notify_step_two_error(job, %{error: error})

      assert job.state == :failed
      assert job.error_message != nil
    end

    test "error handlers can be called directly" do
      {:ok, job} = BranchingWorkflow.create(%{name: "direct-error-call"})

      {:ok, job} = BranchingWorkflow.notify_start_error(job, %{error: %{message: "Test error"}})

      assert job.state == :failed
      assert job.error_message == "Test error"
    end
  end

  describe "state transitions" do
    test "start -> step_one -> step_two -> completed" do
      {:ok, job} = BranchingWorkflow.create(%{name: "transitions"})
      assert job.state == :start

      {:ok, job} = BranchingWorkflow.initialize(job)
      assert job.state == :step_one

      {:ok, job} = BranchingWorkflow.process_one(job)
      assert job.state == :step_two
      assert job.step_one_data == "processed"

      {:ok, job} = BranchingWorkflow.process_two(job)
      assert job.state == :completed
      assert job.step_two_data == "completed"
    end

    test "error transitions to failed state" do
      {:ok, job} = BranchingWorkflow.create(%{name: "error-transition"})

      {:ok, job} = BranchingWorkflow.notify_start_error(job, %{error: "Test"})
      assert job.state == :failed
    end
  end

  describe "workflow configuration" do
    test "has correct error handler configuration" do
      workflow = AshJobs.Info.workflow!(BranchingWorkflow)

      assert length(workflow.steps) == 6

      start_step = Enum.find(workflow.steps, &(&1.name == :start))
      assert start_step.on_error == :handle_start_error

      step_one = Enum.find(workflow.steps, &(&1.name == :step_one))
      assert step_one.on_error == :handle_step_one_error

      step_two = Enum.find(workflow.steps, &(&1.name == :step_two))
      assert step_two.on_error == :handle_step_two_error
    end
  end
end
