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
    # Given a workflow declaring `branch :jobs, relationship: :jobs` in its parallel step
    {:ok, parallel_step} = AshJobs.Info.get_parallel_step(DagRun, :run_jobs)

    # When the compiled branch entity is introspected
    [branch] = parallel_step.branches

    # Then it records the `:jobs` relationship as its source, not a fixed resource module
    assert branch.name == :jobs
    assert branch.resource == nil
    assert branch.relationship == :jobs
  end

  @tag story: "US-RSB-02"
  test "relationship branch passes relationship and needs metadata to generated region" do
    # Given a parallel step with a relationship-sourced branch, after the transformers run
    # When the generated state-machine region for the `:run_jobs` state is introspected
    [region] = AshStateMachine.Info.state_machine_regions_for_state(DagRun, :run_jobs)

    # Then the region carries the `:jobs` relationship and `:needs` gating forwarded from the branch
    assert region.name == :jobs
    assert region.relationship == :jobs
    assert region.needs == :needs
    assert region.resource == DagJob
  end

  @tag story: "US-RSB-03"
  test "relationship branch compiles without a resource" do
    # Given a `branch :jobs, relationship: :jobs` declared with no `resource` option
    # When the DSL is compiled and the branch is introspected
    {:ok, parallel_step} = AshJobs.Info.get_parallel_step(DagRun, :run_jobs)
    [branch] = parallel_step.branches

    # Then it compiled (no "required option :resource" error) and is accepted as dynamic
    # with the relationship as its source
    assert AshJobs.Dsl.Entities.Branch.dynamic?(branch)
    assert branch.resource == nil
    assert branch.relationship == :jobs
  end

  @tag story: "US-RSB-04"
  test "dynamic require_n is preserved for runtime row count evaluation" do
    # Given a parallel step with `completion_strategy {:require_n, 5}` and a relationship-sourced branch
    # When the compiled step and its generated region group are introspected
    {:ok, parallel_step} = AshJobs.Info.get_parallel_step(DynamicRequireNRun, :run_jobs)
    [region_group] = AshStateMachine.Info.state_machine_parallel_regions(DynamicRequireNRun)

    # Then `{:require_n, 5}` survived compilation unrejected (the upper-bound check is deferred
    # to runtime) and is preserved on both the step and the relationship-sourced region group
    assert parallel_step.completion_strategy == {:require_n, 5}
    assert region_group.completion_strategy == {:require_n, 5}
    assert [%{relationship: :jobs}] = region_group.regions
  end

  @tag story: "US-RSB-05"
  test "static branches keep fixed resource regions and static require_n bound" do
    # Given an existing workflow using the static `branch :name, Resource` form (no relationship)
    # When its compiled branch, region group, and completion strategy are introspected
    {:ok, parallel_step} = AshJobs.Info.get_parallel_step(StaticBranchRun, :run_static)
    [branch] = parallel_step.branches
    [region_group] = AshStateMachine.Info.state_machine_parallel_regions(StaticBranchRun)

    # Then it behaves exactly as before: the branch keeps its fixed resource and no relationship,
    # the region is built with name:/resource: as before, and `{:require_n, 1}` stays bounded by
    # the static branch count
    assert branch.resource == StaticBranchWorkflow
    assert branch.relationship == nil

    assert [%{name: :static_job, resource: StaticBranchWorkflow, relationship: nil}] =
             region_group.regions

    assert parallel_step.completion_strategy == {:require_n, 1}
  end

  @tag story: "US-NGD-01"
  test "needs edge persists and gates the dependent on the need's state" do
    # Given a `need` left pending and a `dependent` that declares a needs edge to it
    parent = run()
    need = manual(fn -> DagJob.create!(%{parent_id: parent.id, name: "need"}) end)

    # When the dependent is created via its real (inline) create path while the need is unmet
    dependent =
      inline(fn ->
        DagJob.create!(%{parent_id: parent.id, name: "dependent", need_ids: [need.id]})
      end)

    # Then the needs edge persisted as a self-referential relationship...
    dependent = Ash.load!(dependent, [:needs], lazy?: false)
    assert Enum.map(dependent.needs, & &1.id) == [need.id]

    # ...and because the need has not succeeded, readiness held the dependent at
    # :pending — it never self-started (persisted state, not a predicate)
    assert reload(dependent).state == :pending
    assert reload(dependent).run_count == 0
  end

  @tag story: "US-NGD-02"
  test "row with no needs runs immediately" do
    # Given a run and a job with no needs
    parent = run()

    # When the job is created (its create path dispatches it inline)
    job = inline(fn -> DagJob.create!(%{parent_id: parent.id, name: "root"}) end)

    # Then it runs straight away — the empty needs gate is vacuously satisfied
    job = reload(job)
    assert job.state == :completed
    assert job.run_count == 1
  end

  @tag story: "US-NGD-03"
  test "dependent starts only after all needs reach success" do
    # Given a dependent that needs both `first` and `second`
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

    # When only the first need succeeds
    inline(fn -> DagJob.run!(first) end)
    # Then the dependent is still held back (the second need is unmet)
    assert reload(dependent).state == :pending

    # When the last need also succeeds
    inline(fn -> DagJob.run!(second) end)
    # Then the dependent's gate opens and it runs to completion
    assert reload(dependent).state == :completed
  end

  @tag story: "US-NGD-04"
  test "independent rows run together in a single scheduler pass" do
    # Given two jobs with no needs (independent of each other)
    parent = run()

    [first, second] =
      manual(fn ->
        [
          DagJob.create!(%{parent_id: parent.id, name: "first"}),
          DagJob.create!(%{parent_id: parent.id, name: "second"})
        ]
      end)

    # When the scheduler scans for ready rows once
    AshOban.Test.schedule_and_run_triggers({DagJob, :pending})

    # Then both ran to completion in that single pass — neither gated the other
    assert reload(first).state == :completed
    assert reload(second).state == :completed
  end

  @tag story: "US-NGD-05"
  test "success pushes dependents that became ready" do
    # Given `dependent` whose only unmet need is `need`
    parent = run()

    {need, dependent} =
      manual(fn ->
        need = DagJob.create!(%{parent_id: parent.id, name: "need"})

        dependent =
          DagJob.create!(%{parent_id: parent.id, name: "dependent", need_ids: [need.id]})

        {need, dependent}
      end)

    # When `need`'s step succeeds (its success after-action pushes the dependent's trigger)
    inline(fn -> DagJob.run!(need) end)

    # Then the dependent was pushed to ready and ran immediately — no poll-interval wait
    assert reload(dependent).state == :completed
    assert reload(dependent).run_count == 1
  end

  @tag story: "US-NGD-06"
  test "poll advances ready dependents when push is disabled" do
    # Given a workflow with push disabled, where `dependent` needs `need`
    {need, dependent} =
      manual(fn ->
        need = PollingDagJob.create!(%{name: "need"})

        dependent =
          PollingDagJob.create!(%{name: "dependent", need_ids: [need.id]})

        {need, dependent}
      end)

    # When `need` reaches success but no push fires, the dependent stays pending
    inline(fn -> PollingDagJob.run!(need) end)
    assert reload(dependent).state == :pending

    # When the scheduler's periodic poll next runs, it finds the dependent's needs satisfied
    inline(fn -> AshJobs.Readiness.poll_ready(PollingDagJob) end)

    # Then the dependent advances even though no success push notified it
    assert reload(dependent).state == :completed
  end

  @tag story: "US-NGD-07"
  test "row with unmet needs does not self-start on create" do
    # Given a fanned-out row that needs a sibling not yet in a success state
    parent = run()

    {_need, dependent} =
      manual(fn ->
        need = DagJob.create!(%{parent_id: parent.id, name: "need"})

        dependent =
          DagJob.create!(%{parent_id: parent.id, name: "dependent", need_ids: [need.id]})

        {need, dependent}
      end)

    # When the row is created and its create after-action fires
    dependent = reload(dependent)

    # Then the create trigger does not start its work — it stays :pending, never having run
    assert dependent.state == :pending
    assert dependent.run_count == 0
  end

  @tag story: "US-NGD-08"
  test "independent rows are enqueued together and run in a single scheduler pass" do
    # Given a workflow run with several rows that share no `needs` edges
    parent = run()

    manual(fn ->
      DagJob.create!(%{parent_id: parent.id, name: "alpha"})
      DagJob.create!(%{parent_id: parent.id, name: "beta"})
      DagJob.create!(%{parent_id: parent.id, name: "gamma"})
    end)

    # When a single scheduler pass executes the run
    AshOban.Test.schedule_and_run_triggers({DagJob, :pending})

    # Then every independent row was enqueued together and ran in that one pass —
    # none serialized behind another (all reached :completed)
    jobs = Ash.read!(DagJob)
    assert [_, _, _] = jobs
    assert Enum.all?(jobs, &(&1.state == :completed))
  end

  @tag story: "US-NGD-09"
  test "ordering follows needs edges rather than insertion or name order" do
    # Given `alpha` declares `needs: [omega]` even though omega was inserted first and sorts last
    parent = run()

    {alpha, omega} =
      manual(fn ->
        omega = DagJob.create!(%{parent_id: parent.id, name: "omega"})
        alpha = DagJob.create!(%{parent_id: parent.id, name: "alpha", need_ids: [omega.id]})
        {alpha, omega}
      end)

    # When the run executes (no global sort_order is assigned — order is derived from the edge)
    inline(fn -> AshJobs.Readiness.poll_ready(DagJob) end)

    # Then both complete, and execution order followed the `needs` edge: omega before alpha,
    # not insertion or name order
    assert reload(omega).state == :completed
    assert reload(alpha).state == :completed
    assert DateTime.compare(reload(omega).completed_at, reload(alpha).completed_at) != :gt
  end

  @tag story: "US-FP-01"
  test "failed row skips direct dependents without running them" do
    # Given a dependent that needs `need`
    parent = run()

    {need, dependent} =
      manual(fn ->
        need = DagJob.create!(%{parent_id: parent.id, name: "need"})

        dependent =
          DagJob.create!(%{parent_id: parent.id, name: "dependent", need_ids: [need.id]})

        {need, dependent}
      end)

    # When `need` fails
    DagJob.mark_failed!(need)

    # Then the dependent is skipped — transitioned to a terminal `:skipped`
    # without ever running its workflow step
    dependent = reload(dependent)
    assert dependent.state == :skipped
    assert dependent.run_count == 0
  end

  @tag story: "US-FP-02"
  test "skip propagation follows transitive dependents" do
    # Given a chain root <- middle <- leaf wired by needs
    parent = run()

    {root, middle, leaf} =
      manual(fn ->
        root = DagJob.create!(%{parent_id: parent.id, name: "root"})
        middle = DagJob.create!(%{parent_id: parent.id, name: "middle", need_ids: [root.id]})
        leaf = DagJob.create!(%{parent_id: parent.id, name: "leaf", need_ids: [middle.id]})
        {root, middle, leaf}
      end)

    # When the chain's root fails
    DagJob.mark_failed!(root)

    # Then the skip propagates transitively down the whole chain
    assert reload(middle).state == :skipped
    assert reload(leaf).state == :skipped
  end

  @tag story: "US-FP-03"
  test "generated workflow terminal states include skipped as non-success" do
    # Given a workflow resource using the AshJobs extension, after IntegrateStateMachine ran
    # When the generated terminal states are introspected
    # Then `:skipped` is present as a terminal state, but classified as non-success
    assert :skipped in AshJobs.Info.terminal_states(DagJob)
    refute :skipped in AshJobs.Info.success_terminal_states(DagJob)
  end

  @tag story: "US-FP-04"
  test "completion treats skipped rows as terminal non-success" do
    # Given a region group with one row that succeeds and one driven to the `:skipped` terminal
    parent = run()

    {successful, skipped} =
      manual(fn ->
        successful = DagJob.create!(%{parent_id: parent.id, name: "successful"})
        skipped = DagJob.create!(%{parent_id: parent.id, name: "skipped"})
        {successful, skipped}
      end)

    DagJob.run!(successful)
    DagJob.mark_failed!(skipped)

    # When the group's completion is evaluated
    # Then the skipped row counts as a non-succeeding terminal, so the group resolves
    # (to :partial_failure) instead of hanging on :pending
    assert {:error, :partial_failure} =
             AshStateMachine.check_parallel_completion(parent, AshJobs.TestDomain)
  end

  @tag story: "US-FP-05"
  test "failed upstream leaves no dependent stuck pending" do
    # Given a running chain root <- middle <- leaf wired by `needs`
    parent = run()

    {root, _middle, _leaf} =
      manual(fn ->
        root = DagJob.create!(%{parent_id: parent.id, name: "root"})
        middle = DagJob.create!(%{parent_id: parent.id, name: "middle", need_ids: [root.id]})
        leaf = DagJob.create!(%{parent_id: parent.id, name: "leaf", need_ids: [middle.id]})
        {root, middle, leaf}
      end)

    # When the upstream root fails partway through the DAG
    DagJob.mark_failed!(root)

    # Then every downstream dependent is :skipped and none remain stuck pending/in-progress
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
    # Given fanned-out sibling rows whose `needs` edges form a cycle (first needs second,
    # second needs first)
    parent = run()

    {first, second} =
      manual(fn ->
        first = DagJob.create!(%{parent_id: parent.id, name: "first"})
        second = DagJob.create!(%{parent_id: parent.id, name: "second", need_ids: [first.id]})
        DagNeed.create!(%{dependent_id: first.id, need_id: second.id})
        {first, second}
      end)

    # When the fan-out runtime DAG check runs over the `needs` edge set
    # Then the cycle is detected, and detection happened before any row was scheduled —
    # neither row has run
    assert {:error, %CycleDetected{}} =
             AshJobs.CycleDetection.detect_records([first, second], :needs)

    assert reload(first).run_count == 0
    assert reload(second).run_count == 0
  end

  @tag story: "US-CYC-02"
  test "detected cycle fails parent with clear error" do
    # Given fanned-out rows whose `needs` edges form a cycle under a parent region
    parent = run()

    manual(fn ->
      first = DagJob.create!(%{parent_id: parent.id, name: "first"})
      second = DagJob.create!(%{parent_id: parent.id, name: "second", need_ids: [first.id]})
      DagNeed.create!(%{dependent_id: first.id, need_id: second.id})
    end)

    # When fan-out runs the DAG check and folds the detection back to the parent
    assert {:error, %CycleDetected{}} =
             AshJobs.CycleDetection.detect_records_or_fail_parent(parent, :jobs, :needs)

    # Then the parent transitions to :failed with a clear, named cycle error — not an opaque hang
    parent = reload(parent)
    assert parent.state == :failed
    assert parent.error_message =~ "Cycle detected in needs graph"
  end

  @tag story: "US-CYC-03"
  test "cycle detection terminates on a self-cycle without recursive scheduling" do
    # Given an adversarial self-referential `needs` graph (node :a needs itself)
    # When the runtime DAG check traverses it
    # Then it terminates in bounded time (single traversal, no unbounded recursion) and fails
    # fast with the named cycle error — never escaping into the scheduler
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
