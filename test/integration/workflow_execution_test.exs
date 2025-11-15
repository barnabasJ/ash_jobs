defmodule AshJobs.Integration.WorkflowExecutionTest do
  @moduledoc """
  Integration tests that verify AshJobs workflows actually execute.

  These tests create real resources, execute actions, verify state transitions,
  and test Oban integration with actual job scheduling and execution.
  """

  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.TestResources.OrderFulfillmentJob

  setup do
    TestRepo.delete_all(OrderFulfillmentJob)

    :ok
  end

  describe "workflow resource creation and structure" do
    test "creates a workflow job with initial state" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "TEST-001"})

      assert job.order_id == "TEST-001"
      assert job.state == :load_order
      assert is_binary(job.id)
    end

    test "creating a job triggers the first workflow step" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "CREATE-TRIGGER-001"})
      assert job.state == :load_order

      Oban.drain_queue(queue: :orders)
      Oban.drain_queue(queue: :orders)

      updated_job = TestRepo.get!(OrderFulfillmentJob, job.id)
      assert updated_job.state == :validate_inventory
      assert updated_job.order_data != nil
    end

    test "workflow has all extensions loaded" do
      extensions = Spark.extensions(OrderFulfillmentJob)

      assert AshJobs in extensions
      assert AshStateMachine in extensions
      assert AshOban in extensions
    end
  end

  describe "workflow step execution" do
    test "executes load_order action and transitions state" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "TEST-002"})
      assert job.state == :load_order
      assert job.order_data == nil

      AshOban.schedule(job, :load_order)
      Oban.drain_queue(queue: :orders)
      Oban.drain_queue(queue: :orders)

      updated_job = TestRepo.get!(OrderFulfillmentJob, job.id)
      assert updated_job.state == :validate_inventory
      assert updated_job.order_data != nil
      assert updated_job.order_data["loaded_at"] != nil
      assert updated_job.order_data["items"] != nil
    end

    test "executes multi-step workflow to completion" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "TEST-003"})
      assert job.state == :load_order

      AshOban.Test.schedule_and_run_triggers(OrderFulfillmentJob)

      Oban.drain_queue(queue: :inventory)
      Oban.drain_queue(queue: :inventory)

      Oban.drain_queue(queue: :shipping)
      Oban.drain_queue(queue: :shipping)

      job = TestRepo.get!(OrderFulfillmentJob, job.id)
      assert job.state == :completed
      assert job.inventory_valid == true
      assert job.shipment_id != nil
      assert String.starts_with?(job.shipment_id, "SHIP-")
    end

    test "persists data between workflow steps" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "TEST-004"})

      AshOban.schedule(job, :load_order)
      Oban.drain_queue(queue: :orders)
      Oban.drain_queue(queue: :orders)

      reloaded = TestRepo.get!(OrderFulfillmentJob, job.id)
      order_data = reloaded.order_data
      assert reloaded.order_data != nil
      assert reloaded.state == :validate_inventory

      Oban.drain_queue(queue: :inventory)
      Oban.drain_queue(queue: :inventory)

      reloaded = TestRepo.get!(OrderFulfillmentJob, job.id)
      assert reloaded.inventory_valid == true
      assert reloaded.order_data == order_data
    end
  end

  describe "workflow introspection" do
    test "Info.workflow/1 returns workflow configuration" do
      {:ok, workflow} = AshJobs.Info.workflow(OrderFulfillmentJob)

      assert workflow
      assert workflow.state_attribute == :state
      assert length(workflow.steps) > 0
    end

    test "Info.steps/1 returns all workflow steps" do
      steps = AshJobs.Info.steps(OrderFulfillmentJob)

      step_names = Enum.map(steps, & &1.name)
      assert :load_order in step_names
      assert :validate_inventory in step_names
      assert :create_shipment in step_names
      assert :handle_load_error in step_names
      assert :handle_inventory_error in step_names
    end

    test "Info.entry_points/1 returns initial step" do
      entry_points = AshJobs.Info.entry_points(OrderFulfillmentJob)

      assert length(entry_points) == 1
      assert List.first(entry_points).name == :load_order
    end

    test "Info.terminal_steps/1 returns steps that lead to terminal states" do
      terminal_steps = AshJobs.Info.terminal_steps(OrderFulfillmentJob)

      terminal_step_names = Enum.map(terminal_steps, & &1.name)
      assert :create_shipment in terminal_step_names
      assert :handle_load_error in terminal_step_names
      assert :handle_inventory_error in terminal_step_names
    end

    test "Info.step/2 returns specific step configuration" do
      {:ok, step} = AshJobs.Info.step(OrderFulfillmentJob, :load_order)

      assert step.name == :load_order
      assert step.action == :load_order_data
      assert step.on_success == :validate_inventory
      assert step.on_error == :handle_load_error
      assert step.queue == :orders
    end
  end

  describe "error handling" do
    test "error handler steps have generated actions" do
      actions = Ash.Resource.Info.actions(OrderFulfillmentJob)
      action_names = Enum.map(actions, & &1.name)

      assert :notify_load_error in action_names
      assert :notify_inventory_error in action_names
    end

    test "error handler actions accept error argument" do
      actions = Ash.Resource.Info.actions(OrderFulfillmentJob)
      error_action = Enum.find(actions, &(&1.name == :notify_load_error))

      assert error_action
      assert error_action.type == :update

      error_arg = Enum.find(error_action.arguments, &(&1.name == :error))
      assert error_arg
    end

    test "error handler transitions to failed state" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "ERROR-001"})
      assert job.state == :load_order

      {:ok, job} = OrderFulfillmentJob.notify_load_error(job, %{error: %{message: "Test error"}})

      assert job.state == :failed
      assert job.error_message == "Test error"
    end

    test "error handler in middle of workflow transitions to failed" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "ERROR-002"})

      Oban.drain_queue(queue: :orders)
      Oban.drain_queue(queue: :orders)

      job = TestRepo.get!(OrderFulfillmentJob, job.id)
      assert job.state == :validate_inventory

      {:ok, job} =
        OrderFulfillmentJob.notify_inventory_error(job, %{
          error: %{message: "Inventory check failed"}
        })

      assert job.state == :failed
      assert job.error_message == "Inventory check failed"
    end
  end

  describe "state machine integration" do
    test "validates state transitions" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "TEST-005"})
      assert job.state == :load_order

      result =
        job
        |> Ash.Changeset.for_update(:update, %{state: :completed})
        |> Ash.update()

      assert {:error, _} = result
    end

    test "allows valid state transitions through actions" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "TEST-006"})

      {:ok, updated} = OrderFulfillmentJob.load_order_data(job)
      assert updated.state == :validate_inventory
    end
  end

  describe "Oban trigger configuration" do
    test "workflow steps have Oban trigger configuration" do
      steps = AshJobs.Info.steps(OrderFulfillmentJob)

      load_step = Enum.find(steps, &(&1.name == :load_order))
      assert load_step.trigger == true
      assert load_step.queue == :orders

      validate_step = Enum.find(steps, &(&1.name == :validate_inventory))
      assert validate_step.trigger == true
      assert validate_step.queue == :inventory

      shipment_step = Enum.find(steps, &(&1.name == :create_shipment))
      assert shipment_step.trigger == true
      assert shipment_step.queue == :shipping
    end
  end

  describe "Oban job execution" do
    test "workflow actions schedule Oban jobs" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "OBAN-001"})
      assert job.state == :load_order

      AshOban.schedule(job, :load_order)

      scheduler_jobs = all_enqueued(queue: :orders)

      assert length(scheduler_jobs) > 0
    end

    test "Oban workers execute workflow steps automatically" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "OBAN-002"})
      assert job.state == :load_order

      AshOban.schedule(job, :load_order)
      Oban.drain_queue(queue: :orders)
      Oban.drain_queue(queue: :orders)

      job = TestRepo.get!(OrderFulfillmentJob, job.id)
      assert job.state == :validate_inventory

      Oban.drain_queue(queue: :inventory)
      Oban.drain_queue(queue: :inventory)

      reloaded = TestRepo.get!(OrderFulfillmentJob, job.id)
      assert reloaded.state == :create_shipment
    end

    test "workflow progresses through multiple Oban job executions" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "OBAN-003"})
      assert job.state == :load_order

      AshOban.schedule(job, :load_order)
      Oban.drain_queue(queue: :orders)
      Oban.drain_queue(queue: :orders)

      job = TestRepo.get!(OrderFulfillmentJob, job.id)
      assert job.state == :validate_inventory

      Oban.drain_queue(queue: :inventory)
      Oban.drain_queue(queue: :inventory)

      job = TestRepo.get!(OrderFulfillmentJob, job.id)
      assert job.state == :create_shipment
      assert job.inventory_valid == true

      Oban.drain_queue(queue: :shipping)
      Oban.drain_queue(queue: :shipping)

      job = TestRepo.get!(OrderFulfillmentJob, job.id)
      assert job.state == :completed
      assert job.shipment_id != nil
    end

    test "Oban jobs are scheduled in correct queues" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "OBAN-004"})

      AshOban.schedule(job, :load_order)
      Oban.drain_queue(queue: :orders)

      AshOban.schedule(TestRepo.get!(OrderFulfillmentJob, job.id), :validate_inventory)
      inventory_jobs = all_enqueued(queue: :inventory)
      assert length(inventory_jobs) > 0
    end
  end

  describe "complete workflow scenarios" do
    test "full happy path workflow execution" do
      {:ok, job} = OrderFulfillmentJob.create(%{order_id: "HAPPY-001"})
      assert job.state == :load_order

      AshOban.schedule(job, :load_order)
      Oban.drain_queue(queue: :orders)
      Oban.drain_queue(queue: :orders)

      Oban.drain_queue(queue: :inventory)
      Oban.drain_queue(queue: :inventory)

      Oban.drain_queue(queue: :shipping)
      Oban.drain_queue(queue: :shipping)

      job = TestRepo.get!(OrderFulfillmentJob, job.id)
      assert job.state == :completed
      assert job.order_data != nil
      assert job.inventory_valid == true
      assert job.shipment_id != nil
      assert job.error_message == nil
    end

    test "workflow with multiple jobs running concurrently" do
      {:ok, job1} = OrderFulfillmentJob.create(%{order_id: "CONCURRENT-001"})
      {:ok, job2} = OrderFulfillmentJob.create(%{order_id: "CONCURRENT-002"})
      {:ok, job3} = OrderFulfillmentJob.create(%{order_id: "CONCURRENT-003"})

      AshOban.schedule(job1, :load_order)
      AshOban.schedule(job2, :load_order)
      AshOban.schedule(job3, :load_order)

      Oban.drain_queue(queue: :orders)
      Oban.drain_queue(queue: :orders)

      job1 = TestRepo.get!(OrderFulfillmentJob, job1.id)
      job2 = TestRepo.get!(OrderFulfillmentJob, job2.id)
      job3 = TestRepo.get!(OrderFulfillmentJob, job3.id)
      assert job1.state == :validate_inventory
      assert job2.state == :validate_inventory
      assert job3.state == :validate_inventory

      Oban.drain_queue(queue: :inventory)
      Oban.drain_queue(queue: :inventory)

      Oban.drain_queue(queue: :shipping)
      Oban.drain_queue(queue: :shipping)

      job1 = TestRepo.get!(OrderFulfillmentJob, job1.id)
      job2 = TestRepo.get!(OrderFulfillmentJob, job2.id)
      job3 = TestRepo.get!(OrderFulfillmentJob, job3.id)
      assert job1.state == :completed
      assert job2.state == :completed
      assert job3.state == :completed

      assert job1.shipment_id != job2.shipment_id
      assert job2.shipment_id != job3.shipment_id
    end
  end
end
