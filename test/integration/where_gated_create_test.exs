defmodule AshJobs.Integration.WhereGatedCreateTest do
  @moduledoc """
  US-NGD-10 — the direct enqueue path honors the trigger's generated `where`.

  `AshOban.run_trigger/2` inserts an Oban job without evaluating the trigger's
  `where`, so before this gate the create path could enqueue a row that the
  worker immediately cancelled. This suite's single canonical owner test
  drives the real create action, the real `AshJobs.Readiness.run_trigger_if_ready/2`
  helper, and a policy-protected resource, and asserts on persisted Oban rows
  and row state — no mocked schedulers.
  """
  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.Readiness
  alias AshJobs.TestResources.PolicyGatedJob
  alias AshJobs.TestResources.WhereGatedJob

  setup do
    TestRepo.delete_all(AshJobs.TestResources.WhereGatedNeed)
    TestRepo.delete_all(WhereGatedJob)
    TestRepo.delete_all(PolicyGatedJob)
    :ok
  end

  defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

  # The generated worker for the `:pending` entry step of `WhereGatedJob`.
  defp gated_pending_worker, do: Oban.Worker.to_string(WhereGatedJob.AshOban.Worker.Pending)

  defp policy_pending_worker, do: Oban.Worker.to_string(PolicyGatedJob.AshOban.Worker.Pending)

  defp enqueued_jobs(worker, states \\ ["available", "scheduled", "retryable", "executing"]) do
    Oban.Job
    |> where(worker: ^Oban.Worker.to_string(worker))
    |> where([j], j.state in ^states)
    |> TestRepo.all()
  end

  defp reload(%WhereGatedJob{id: id}), do: WhereGatedJob.get_by_id!(id)

  @tag story: "US-NGD-10"
  test "the direct enqueue path honors the trigger's where, including under policies" do
    # Given a resource whose entry step carries `where expr(admitted == true)`
    # When a row is created with the gate CLOSED through the real create
    # action (whose after-action runs the direct trigger)
    closed_row = manual(fn -> WhereGatedJob.create!(%{name: "gated", admitted: false}) end)

    # Then nothing is enqueued and the helper stays silent for callers that
    # cannot know the gate state (a push, a resume)
    assert [] = enqueued_jobs(gated_pending_worker())

    assert :not_ready =
             Readiness.run_trigger_if_ready(WhereGatedJob.get_by_id!(closed_row.id), :pending)

    assert [] = enqueued_jobs(gated_pending_worker())

    # And when the gate opens, the same helper enqueues exactly once and the
    # real generated worker runs the row to its success terminal
    opened = WhereGatedJob.admit!(closed_row)
    assert %Oban.Job{} = Readiness.run_trigger_if_ready(opened, :pending)
    assert [%Oban.Job{}] = enqueued_jobs(gated_pending_worker())

    AshOban.Test.schedule_and_run_triggers({WhereGatedJob, :pending})
    assert reload(opened).state == :completed
    assert reload(opened).run_count == 1

    # And a row created with the gate OPEN dispatches at create time and runs
    open_row =
      manual(fn -> WhereGatedJob.create!(%{name: "open", admitted: true}) end)

    assert [%Oban.Job{}] = enqueued_jobs(gated_pending_worker())

    AshOban.Test.schedule_and_run_triggers({WhereGatedJob, :pending})
    assert reload(open_row).state == :completed

    # And a POLICY-PROTECTED resource — readable only through the AshOban
    # interaction context the generated scheduler and worker supply — is
    # dispatched by the real helper and run by the real worker: a plain read
    # is refused, proving the policy is real, so the helper must have answered
    # its `where` read under the same authorization semantics
    seeded = PolicyGatedJob.create!(%{name: "policy", admitted: true}, authorize?: false)

    assert_raise Ash.Error.Forbidden, fn ->
      Ash.read!(PolicyGatedJob, authorize?: true)
    end

    assert %Oban.Job{} = Readiness.run_trigger_if_ready(seeded, :pending)
    assert [%Oban.Job{}] = enqueued_jobs(policy_pending_worker())

    AshOban.Test.schedule_and_run_triggers({PolicyGatedJob, :pending})
    [rerun] = Ash.read!(PolicyGatedJob, authorize?: false)
    assert rerun.state == :completed
    assert rerun.run_count == 1
  end
end
