defmodule AshJobs.Integration.RuntimeDagWorkflowTest do
  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.Errors.CycleDetected
  alias AshJobs.TestResources.DagJob
  alias AshJobs.TestResources.DagNeed
  alias AshJobs.TestResources.DagRun
  alias AshJobs.TestResources.DynamicRequireNRun
  alias AshJobs.TestResources.PollingDagJob
  alias AshJobs.TestResources.StaticBranchRun
  alias AshJobs.TestResources.StaticBranchWorkflow

  setup do
    TestRepo.delete_all(DagNeed)
    TestRepo.delete_all(DagJob)
    TestRepo.delete_all(DagRun)
    TestRepo.delete_all(AshJobs.TestResources.PollingDagNeed)
    TestRepo.delete_all(PollingDagJob)
    :ok
  end

  defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)
  defp inline(fun), do: Oban.Testing.with_testing_mode(:inline, fun)

  defp run do
    DagRun.create!(%{name: "runtime-dag"})
  end

  defp reload(%resource{id: id}) do
    resource
    |> Ash.get!(id)
  end

  @tag story: "US-RSB-01"
  test "relationship branch records runtime row source instead of fixed resource" do
    {:ok, parallel_step} = AshJobs.Info.get_parallel_step(DagRun, :run_jobs)
    [branch] = parallel_step.branches

    assert branch.name == :jobs
    assert branch.resource == nil
    assert branch.relationship == :jobs
  end

  @tag story: "US-RSB-02"
  test "relationship branch passes relationship and needs metadata to generated region" do
    [region] = AshStateMachine.Info.state_machine_regions_for_state(DagRun, :run_jobs)

    assert region.name == :jobs
    assert region.relationship == :jobs
    assert region.needs == :needs
    assert region.resource == DagJob
  end

  @tag story: "US-RSB-03"
  test "relationship branch compiles without a resource" do
    {:ok, parallel_step} = AshJobs.Info.get_parallel_step(DagRun, :run_jobs)
    [branch] = parallel_step.branches

    assert AshJobs.Dsl.Entities.Branch.dynamic?(branch)
    assert branch.resource == nil
    assert branch.relationship == :jobs
  end

  @tag story: "US-RSB-04"
  test "dynamic require_n is preserved for runtime row count evaluation" do
    {:ok, parallel_step} = AshJobs.Info.get_parallel_step(DynamicRequireNRun, :run_jobs)
    [region_group] = AshStateMachine.Info.state_machine_parallel_regions(DynamicRequireNRun)

    assert parallel_step.completion_strategy == {:require_n, 5}
    assert region_group.completion_strategy == {:require_n, 5}
    assert [%{relationship: :jobs}] = region_group.regions
  end

  @tag story: "US-RSB-05"
  test "static branches keep fixed resource regions and static require_n bound" do
    {:ok, parallel_step} = AshJobs.Info.get_parallel_step(StaticBranchRun, :run_static)
    [branch] = parallel_step.branches
    [region_group] = AshStateMachine.Info.state_machine_parallel_regions(StaticBranchRun)

    assert branch.resource == StaticBranchWorkflow
    assert branch.relationship == nil

    assert [%{name: :static_job, resource: StaticBranchWorkflow, relationship: nil}] =
             region_group.regions

    assert parallel_step.completion_strategy == {:require_n, 1}
  end

  @tag story: "US-NGD-01"
  test "needs edge persists and readiness consults the target state" do
    parent = run()

    {need, dependent} =
      manual(fn ->
        need = DagJob.create!(%{parent_id: parent.id, name: "need"})

        dependent =
          DagJob.create!(%{parent_id: parent.id, name: "dependent", need_ids: [need.id]})

        {need, dependent}
      end)

    dependent = Ash.load!(dependent, [:needs], lazy?: false)

    assert Enum.map(dependent.needs, & &1.id) == [need.id]
    refute AshJobs.Readiness.needs_satisfied?(dependent)
  end

  @tag story: "US-NGD-02"
  test "row with no needs runs immediately" do
    parent = run()

    job = inline(fn -> DagJob.create!(%{parent_id: parent.id, name: "root"}) end)
    job = reload(job)

    assert job.state == :completed
    assert job.run_count == 1
  end

  @tag story: "US-NGD-03"
  test "dependent starts only after all needs reach success" do
    parent = run()

    {first, second, dependent} =
      manual(fn ->
        first = DagJob.create!(%{parent_id: parent.id, name: "first"})
        second = DagJob.create!(%{parent_id: parent.id, name: "second"})

        dependent =
          DagJob.create!(%{
            parent_id: parent.id,
            name: "dependent",
            need_ids: [first.id, second.id]
          })

        {first, second, dependent}
      end)

    inline(fn -> DagJob.run!(first) end)
    assert reload(dependent).state == :pending

    inline(fn -> DagJob.run!(second) end)
    assert reload(dependent).state == :completed
  end

  @tag story: "US-NGD-04"
  test "independent rows are ready in the same scheduler pass" do
    parent = run()

    [first, second] =
      manual(fn ->
        [
          DagJob.create!(%{parent_id: parent.id, name: "first"}),
          DagJob.create!(%{parent_id: parent.id, name: "second"})
        ]
      end)

    ready_ids = DagJob |> AshJobs.Readiness.ready_records() |> Enum.map(& &1.id) |> Enum.sort()

    assert ready_ids == [first.id, second.id] |> Enum.sort()
  end

  @tag story: "US-NGD-05"
  test "success pushes dependents that became ready" do
    parent = run()

    {need, dependent} =
      manual(fn ->
        need = DagJob.create!(%{parent_id: parent.id, name: "need"})

        dependent =
          DagJob.create!(%{parent_id: parent.id, name: "dependent", need_ids: [need.id]})

        {need, dependent}
      end)

    inline(fn -> DagJob.run!(need) end)

    assert reload(dependent).state == :completed
    assert reload(dependent).run_count == 1
  end

  @tag story: "US-NGD-06"
  test "poll advances ready dependents when push is disabled" do
    {need, dependent} =
      manual(fn ->
        need = PollingDagJob.create!(%{name: "need"})

        dependent =
          PollingDagJob.create!(%{name: "dependent", need_ids: [need.id]})

        {need, dependent}
      end)

    inline(fn -> PollingDagJob.run!(need) end)
    assert reload(dependent).state == :pending

    inline(fn -> AshJobs.Readiness.poll_ready(PollingDagJob) end)
    assert reload(dependent).state == :completed
  end

  @tag story: "US-NGD-07"
  test "row with unmet needs does not self-start on create" do
    parent = run()

    {_need, dependent} =
      manual(fn ->
        need = DagJob.create!(%{parent_id: parent.id, name: "need"})

        dependent =
          DagJob.create!(%{parent_id: parent.id, name: "dependent", need_ids: [need.id]})

        {need, dependent}
      end)

    dependent = reload(dependent)

    assert dependent.state == :pending
    assert dependent.run_count == 0
  end

  @tag story: "US-NGD-08"
  test "operator can observe multiple independent rows ready before execution" do
    parent = run()

    manual(fn ->
      DagJob.create!(%{parent_id: parent.id, name: "alpha"})
      DagJob.create!(%{parent_id: parent.id, name: "beta"})
      DagJob.create!(%{parent_id: parent.id, name: "gamma"})
    end)

    ready_names =
      DagJob |> AshJobs.Readiness.ready_records() |> Enum.map(& &1.name) |> Enum.sort()

    assert ready_names == ["alpha", "beta", "gamma"]
  end

  @tag story: "US-NGD-09"
  test "ordering follows needs edges rather than insertion or name order" do
    parent = run()

    {alpha, omega} =
      manual(fn ->
        omega = DagJob.create!(%{parent_id: parent.id, name: "omega"})
        alpha = DagJob.create!(%{parent_id: parent.id, name: "alpha", need_ids: [omega.id]})
        {alpha, omega}
      end)

    inline(fn -> AshJobs.Readiness.poll_ready(DagJob) end)
    assert reload(omega).state == :completed
    assert reload(alpha).state == :completed
    assert DateTime.compare(reload(omega).completed_at, reload(alpha).completed_at) != :gt
  end

  @tag story: "US-NGD-03"
  test "the generated pending trigger where-filter matches only rows with all needs satisfied" do
    parent = run()

    manual(fn ->
      need = DagJob.create!(%{parent_id: parent.id, name: "need"})
      DagJob.create!(%{parent_id: parent.id, name: "dependent", need_ids: [need.id]})
      DagJob.create!(%{parent_id: parent.id, name: "ready"})
    end)

    # The needs gate is declarative: it lives in the AshOban trigger `where`, so
    # the scheduler itself only scans ready rows. Apply that same `where` and
    # confirm the unmet dependent is filtered out while the no-needs rows match.
    pending_where =
      DagJob
      |> AshOban.Info.oban_triggers()
      |> Enum.find(&(&1.name == :pending))
      |> Map.fetch!(:where)

    matched =
      DagJob
      |> Ash.Query.do_filter(pending_where)
      |> Ash.read!()
      |> Enum.map(& &1.name)
      |> Enum.sort()

    assert matched == ["need", "ready"]
  end

  @tag story: "US-FP-01"
  test "failed row skips direct dependents without running them" do
    parent = run()

    {need, dependent} =
      manual(fn ->
        need = DagJob.create!(%{parent_id: parent.id, name: "need"})

        dependent =
          DagJob.create!(%{parent_id: parent.id, name: "dependent", need_ids: [need.id]})

        {need, dependent}
      end)

    DagJob.mark_failed!(need)
    dependent = reload(dependent)

    assert dependent.state == :skipped
    assert dependent.run_count == 0
  end

  @tag story: "US-FP-02"
  test "skip propagation follows transitive dependents" do
    parent = run()

    {root, middle, leaf} =
      manual(fn ->
        root = DagJob.create!(%{parent_id: parent.id, name: "root"})
        middle = DagJob.create!(%{parent_id: parent.id, name: "middle", need_ids: [root.id]})
        leaf = DagJob.create!(%{parent_id: parent.id, name: "leaf", need_ids: [middle.id]})
        {root, middle, leaf}
      end)

    DagJob.mark_failed!(root)

    assert reload(middle).state == :skipped
    assert reload(leaf).state == :skipped
  end

  @tag story: "US-FP-03"
  test "generated workflow terminal states include skipped as non-success" do
    assert :skipped in AshJobs.Info.terminal_states(DagJob)
    refute :skipped in AshJobs.Info.success_terminal_states(DagJob)
  end

  @tag story: "US-FP-04"
  test "completion treats skipped rows as terminal non-success" do
    parent = run()

    {successful, skipped} =
      manual(fn ->
        successful = DagJob.create!(%{parent_id: parent.id, name: "successful"})
        skipped = DagJob.create!(%{parent_id: parent.id, name: "skipped"})
        {successful, skipped}
      end)

    DagJob.run!(successful)
    DagJob.mark_failed!(skipped)

    assert {:error, :partial_failure} =
             AshStateMachine.check_parallel_completion(parent, AshJobs.TestDomain)
  end

  @tag story: "US-FP-05"
  test "failed upstream leaves no dependent stuck pending" do
    parent = run()

    {root, _middle, _leaf} =
      manual(fn ->
        root = DagJob.create!(%{parent_id: parent.id, name: "root"})
        middle = DagJob.create!(%{parent_id: parent.id, name: "middle", need_ids: [root.id]})
        leaf = DagJob.create!(%{parent_id: parent.id, name: "leaf", need_ids: [middle.id]})
        {root, middle, leaf}
      end)

    DagJob.mark_failed!(root)

    states = DagJob |> Ash.read!() |> Enum.map(& &1.state) |> Enum.sort()
    assert states == [:failed, :skipped, :skipped]
  end

  @tag story: "US-FP-06"
  test "cancelled row skips its dependents like a failure" do
    parent = run()

    {need, dependent, leaf} =
      manual(fn ->
        need = DagJob.create!(%{parent_id: parent.id, name: "need"})

        dependent =
          DagJob.create!(%{parent_id: parent.id, name: "dependent", need_ids: [need.id]})

        leaf = DagJob.create!(%{parent_id: parent.id, name: "leaf", need_ids: [dependent.id]})
        {need, dependent, leaf}
      end)

    DagJob.cancel!(need)

    # `:cancelled` is a non-success terminal, so the dependent is skipped (never
    # started) and the skip propagates transitively to the leaf.
    assert reload(need).state == :cancelled
    assert reload(dependent).state == :skipped
    assert reload(dependent).run_count == 0
    assert reload(leaf).state == :skipped
  end

  @tag story: "US-CYC-01"
  test "runtime needs cycle is detected before scheduling rows" do
    parent = run()

    {first, second} =
      manual(fn ->
        first = DagJob.create!(%{parent_id: parent.id, name: "first"})
        second = DagJob.create!(%{parent_id: parent.id, name: "second", need_ids: [first.id]})
        DagNeed.create!(%{dependent_id: first.id, need_id: second.id})
        {first, second}
      end)

    assert {:error, %CycleDetected{}} =
             AshJobs.CycleDetection.detect_records([first, second], :needs)

    assert reload(first).run_count == 0
    assert reload(second).run_count == 0
  end

  @tag story: "US-CYC-02"
  test "detected cycle fails parent with clear error" do
    parent = run()

    manual(fn ->
      first = DagJob.create!(%{parent_id: parent.id, name: "first"})
      second = DagJob.create!(%{parent_id: parent.id, name: "second", need_ids: [first.id]})
      DagNeed.create!(%{dependent_id: first.id, need_id: second.id})
    end)

    assert {:error, %CycleDetected{}} =
             AshJobs.CycleDetection.detect_records_or_fail_parent(parent, :jobs, :needs)

    parent = reload(parent)
    assert parent.state == :failed
    assert parent.error_message =~ "Cycle detected in needs graph"
  end

  @tag story: "US-CYC-03"
  test "cycle detection terminates on a self-cycle without recursive scheduling" do
    assert {:error, %CycleDetected{cycle: [:a, :a]}} = AshJobs.CycleDetection.detect([:a], a: :a)
  end

  @tag story: "US-RSB-06"
  test "a relationship-sourced parallel step finalizes its parent when its branches complete" do
    # Given a run whose `:run_jobs` region fans out over two independent jobs
    parent = run()

    inline(fn ->
      # creating each job self-starts it (no needs) and runs it to `:completed`
      DagJob.create!(%{parent_id: parent.id, name: "a"})
      DagJob.create!(%{parent_id: parent.id, name: "b"})
    end)

    # ...so both branch rows have reached a success terminal state
    assert DagJob |> Ash.read!() |> Enum.map(& &1.state) == [:completed, :completed]

    # When the scheduler scans the parent's completion trigger
    assert %{success: success} =
             AshOban.Test.schedule_and_run_triggers({DagRun, :handle_run_jobs_complete})

    assert success >= 1

    # Then the parent finalizes to `:completed` on its own — no manual
    # `check_parallel_completion` call needed
    assert reload(parent).state == :completed
  end
end
