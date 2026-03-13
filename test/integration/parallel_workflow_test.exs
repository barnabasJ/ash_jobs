defmodule AshJobs.Integration.ParallelWorkflowTest do
  @moduledoc """
  Integration tests for parallel workflow execution.

  Tests the full lifecycle of a workflow with a parallel_step:
  - Parent starts and transitions to the parallel step state
  - Branch resources are activated (created with parent_id)
  - Branch actions are invoked via auto-generated wrapper actions on parent
  - Completion is detected automatically when all branches finish
  - Parent transitions to the next step after parallel completion
  """

  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.TestResources.ParallelWorkflow

  setup do
    TestRepo.delete_all(ParallelWorkflow)
    :ok
  end

  describe "parallel workflow lifecycle" do
    test "completes full lifecycle: start -> parallel branches -> finalize -> completed" do
      # Step 1: Create workflow in initial state
      {:ok, job} = ParallelWorkflow.create(%{name: "test-parallel"})
      assert job.state == :start

      # Step 2: Run the start step to transition to process_parallel
      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :start)
      end)

      job = ParallelWorkflow.get_by_id!(job.id)
      assert job.state == :process_parallel

      # Step 3: Verify branch resources were activated
      job = Ash.load!(job, [:payment, :inventory], domain: AshJobs.TestDomain)
      assert job.payment != nil
      assert job.payment.state == :pending
      assert job.inventory != nil
      assert job.inventory.state == :pending

      # Step 4: Process payment branch via wrapper action
      job =
        job
        |> Ash.Changeset.for_update(:payment_process_payment, %{}, domain: AshJobs.TestDomain)
        |> Ash.update!()

      job = Ash.load!(job, [:payment], domain: AshJobs.TestDomain, lazy?: false)
      assert job.payment.state == :completed
      # Still waiting for inventory
      assert job.state == :process_parallel

      # Step 5: Reserve inventory via wrapper action
      job =
        job
        |> Ash.Changeset.for_update(:inventory_reserve_inventory, %{}, domain: AshJobs.TestDomain)
        |> Ash.update!()

      job = Ash.load!(job, [:inventory], domain: AshJobs.TestDomain, lazy?: false)
      assert job.inventory.state == :reserving
      assert job.state == :process_parallel

      # Step 6: Confirm inventory - this completes all branches
      job =
        job
        |> Ash.Changeset.for_update(:inventory_confirm_inventory, %{}, domain: AshJobs.TestDomain)
        |> Ash.update!()

      # The on_complete callback should fire, transitioning parent to :finalize
      job = ParallelWorkflow.get_by_id!(job.id)
      assert job.state == :finalize

      # Step 7: Run the finalize step
      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :finalize)
      end)

      job = ParallelWorkflow.get_by_id!(job.id)
      assert job.state == :completed
      assert job.result == "finalized"
    end

    test "branches can be progressed in any order" do
      {:ok, job} = ParallelWorkflow.create(%{name: "test-any-order"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :start)
      end)

      job = ParallelWorkflow.get_by_id!(job.id)
      assert job.state == :process_parallel

      # Start with inventory first
      job =
        job
        |> Ash.Changeset.for_update(:inventory_reserve_inventory, %{}, domain: AshJobs.TestDomain)
        |> Ash.update!()

      job =
        job
        |> Ash.Changeset.for_update(:inventory_confirm_inventory, %{}, domain: AshJobs.TestDomain)
        |> Ash.update!()

      # Parent still waiting for payment
      job = ParallelWorkflow.get_by_id!(job.id)
      assert job.state == :process_parallel

      # Now complete payment
      job =
        job
        |> Ash.Changeset.for_update(:payment_process_payment, %{}, domain: AshJobs.TestDomain)
        |> Ash.update!()

      # Both branches done - parent should transition to finalize
      job = ParallelWorkflow.get_by_id!(job.id)
      assert job.state == :finalize
    end

    test "partial completion does not trigger on_complete" do
      {:ok, job} = ParallelWorkflow.create(%{name: "test-partial"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :start)
      end)

      job = ParallelWorkflow.get_by_id!(job.id)

      # Complete only payment
      job =
        job
        |> Ash.Changeset.for_update(:payment_process_payment, %{}, domain: AshJobs.TestDomain)
        |> Ash.update!()

      # Parent should still be in process_parallel
      job = ParallelWorkflow.get_by_id!(job.id)
      assert job.state == :process_parallel
    end
  end

  describe "workflow configuration" do
    test "parallel_step is introspectable" do
      parallel_steps = AshJobs.Info.parallel_steps(ParallelWorkflow)
      assert length(parallel_steps) == 1

      [ps] = parallel_steps
      assert ps.name == :process_parallel
      assert ps.completion_strategy == :all
      assert ps.on_complete == :finalize
      assert length(ps.branches) == 2

      branch_names = Enum.map(ps.branches, & &1.name)
      assert :payment in branch_names
      assert :inventory in branch_names
    end

    test "entry points are identified correctly" do
      entry_points = AshJobs.Info.entry_points(ParallelWorkflow)
      assert length(entry_points) == 1
      assert hd(entry_points).name == :start
    end
  end
end
