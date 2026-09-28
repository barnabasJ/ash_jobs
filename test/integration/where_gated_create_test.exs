defmodule AshJobs.Integration.WhereGatedCreateTest do
  @moduledoc """
  US-NGD-10 — the direct enqueue path honors the trigger's generated `where`.

  `AshOban.run_trigger/2` inserts an Oban job without evaluating the trigger's
  `where`, so before this gate the create path could enqueue a row that the
  worker immediately cancelled. These tests drive the real create action and
  the real `AshJobs.Readiness.run_trigger_if_ready/2` helper and assert on
  persisted Oban rows and row state — no mocked schedulers.
  """
  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.Readiness
  alias AshJobs.TestResources.WhereGatedJob

  setup do
    TestRepo.delete_all(AshJobs.TestResources.WhereGatedNeed)
    TestRepo.delete_all(WhereGatedJob)
    :ok
  end

  defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

  # The generated worker for the `:pending` entry step of `WhereGatedJob`.
  defp pending_worker, do: Oban.Worker.to_string(WhereGatedJob.AshOban.Worker.Pending)

  defp enqueued_pending_jobs do
    Oban.Job
    |> where(worker: ^pending_worker())
    |> TestRepo.all()
  end

  defp reload(%WhereGatedJob{id: id}), do: WhereGatedJob.get_by_id!(id)

  @tag story: "US-NGD-10"
  test "a false custom where prevents create-time enqueue" do
    # Given a resource whose entry step carries `where expr(admitted == true)`
    # When a row is created with the gate closed (`admitted: false`) through
    # the real create action (whose after-action runs the direct trigger)
    _row = manual(fn -> WhereGatedJob.create!(%{name: "gated", admitted: false}) end)

    # Then nothing is enqueued: no Oban job exists for the trigger, and the
    # row stays :pending without ever having run
    assert [] = enqueued_pending_jobs()
  end

  @tag story: "US-NGD-10"
  test "a true custom where lets create-time enqueue proceed and run" do
    # Given the same resource with the gate open
    row = manual(fn -> WhereGatedJob.create!(%{name: "open", admitted: true}) end)

    # Then the create path enqueues exactly one worker job
    assert [%Oban.Job{}] = enqueued_pending_jobs()

    # And that real worker runs the row to its success terminal
    AshOban.Test.schedule_and_run_triggers({WhereGatedJob, :pending})
    assert reload(row).state == :completed
    assert reload(row).run_count == 1
  end

  @tag story: "US-NGD-10"
  test "run_trigger_if_ready enqueues once the where becomes true" do
    # Given a created row whose gate is closed (not enqueued at create)
    row = manual(fn -> WhereGatedJob.create!(%{name: "later"}) end)
    assert [] = enqueued_pending_jobs()

    # When the gate opens and the readiness helper runs — the same helper the
    # create path and the success push use
    row = WhereGatedJob.admit!(row)
    assert %Oban.Job{} = Readiness.run_trigger_if_ready(row, :pending)

    # Then the row is enqueued exactly once and a real scheduler+worker pass
    # completes it
    assert [%Oban.Job{}] = enqueued_pending_jobs()

    AshOban.Test.schedule_and_run_triggers({WhereGatedJob, :pending})
    assert reload(row).state == :completed
  end

  @tag story: "US-NGD-10"
  test "run_trigger_if_ready stays silent while the where is false" do
    # Given a created row whose gate is closed
    row = manual(fn -> WhereGatedJob.create!(%{name: "held"}) end)

    # When callers that cannot know the gate state (a push, a resume) invoke
    # the readiness helper anyway
    assert :not_ready = Readiness.run_trigger_if_ready(reload(row), :pending)

    # Then nothing is enqueued — the helper defers to the same `where` the
    # worker would have cancelled on
    assert [] = enqueued_pending_jobs()
  end
end
