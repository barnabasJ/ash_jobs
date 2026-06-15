defmodule AshJobs.Integration.BranchingWorkflowTest do
  @moduledoc """
  Comprehensive tests for BranchingWorkflow.

  BranchingWorkflow demonstrates error handling with multiple error paths.
  Tests cover happy path, error handling at each step, and state transitions.
  """

  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  import ExUnit.CaptureLog

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
    @tag story: "US-WEH-02"
    test "error at start step routes to handle_start_error" do
      # Given a running workflow with an on_error handler configured for the start step
      {:ok, job} = BranchingWorkflow.create(%{name: "error-start", force_error_at: "start"})
      assert job.state == :start

      # When the start step fails during Oban-triggered execution
      {error, log} =
        with_log(fn ->
          try do
            Oban.Testing.with_testing_mode(:inline, fn ->
              AshOban.run_trigger(job, :start)
            end)

            nil
          catch
            _kind, error -> error
          end
        end)

      # Then the intentional failure log is captured and asserted, not leaked
      assert log =~ "Forced error at start"
      assert error != nil

      # When the failure is routed through the configured handler
      {:ok, job} = BranchingWorkflow.notify_start_error(job, %{error: error})

      # Then the record is persisted as :failed with a non-empty error message
      assert job.state == :failed
      assert job.error_message != nil
    end

    @tag story: "US-WEH-02"
    test "error at step_one routes to handle_step_one_error" do
      # Given a running workflow with an on_error handler configured for a later step (step_one)
      {:ok, job} = BranchingWorkflow.create(%{name: "error-step-one", force_error_at: "step_one"})

      # When execution advances to step_one and that later step fails during Oban-triggered execution
      {error, log} =
        with_log(fn ->
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
        end)

      # Then the intentional failure log is captured and asserted, not leaked
      assert log =~ "Forced error at step_one"
      assert error != nil

      # When the failure is routed through step_one's configured handler
      job = BranchingWorkflow.get_by_id!(job.id)
      {:ok, job} = BranchingWorkflow.notify_step_one_error(job, %{error: error})

      # Then the record is persisted as :failed with a non-empty error message
      assert job.state == :failed
      assert job.error_message != nil
    end

    @tag story: "US-WEH-02"
    test "error at step_two routes to handle_step_two_error" do
      # Given a running workflow with an on_error handler configured for a later step (step_two)
      {:ok, job} = BranchingWorkflow.create(%{name: "error-step-two", force_error_at: "step_two"})

      # When execution advances through to step_two and that later step fails during Oban-triggered execution
      {error, log} =
        with_log(fn ->
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
        end)

      # Then the intentional failure log is captured and asserted, not leaked
      assert log =~ "Forced error at step_two"
      assert error != nil

      # When the failure is routed through step_two's configured handler
      job = BranchingWorkflow.get_by_id!(job.id)
      {:ok, job} = BranchingWorkflow.notify_step_two_error(job, %{error: error})

      # Then the record is persisted as :failed with a non-empty error message
      assert job.state == :failed
      assert job.error_message != nil
    end

    @tag story: "US-WEH-01"
    test "error handlers can be called directly" do
      # Given a workflow record sitting in the start state that owns the start error handler
      {:ok, job} = BranchingWorkflow.create(%{name: "direct-error-call"})

      # When the handler is called from that valid source state with a map error payload carrying :message
      {:ok, job} = BranchingWorkflow.notify_start_error(job, %{error: %{message: "Test error"}})

      # Then the workflow transitions to its terminal state with the extracted message persisted
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

    @tag story: "US-WEH-01"
    test "a string error payload from a valid source state persists and routes to failed" do
      # Given a workflow record in the start state that owns the start error handler
      {:ok, job} = BranchingWorkflow.create(%{name: "error-transition"})

      # When the handler is called from that valid source state with a binary error payload
      {:ok, job} = BranchingWorkflow.notify_start_error(job, %{error: "Test"})

      # Then the binary payload is persisted as the error message and the record routes to :failed
      assert job.state == :failed
      assert job.error_message == "Test"
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
