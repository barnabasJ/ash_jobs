defmodule AshJobs.Info do
  @moduledoc """
  Introspection functions for AshJobs workflows.

  Provides runtime access to workflow configuration and metadata.
  """

  use Spark.InfoGenerator, extension: AshJobs, sections: [:workflow]

  @doc """
  Returns the workflow configuration for a resource.

  Raises if no workflow is defined.

  ## Examples

      workflow = AshJobs.Info.workflow!(MyApp.FulfillmentJob)
      workflow.state_attribute
      #=> :state

      workflow.steps
      #=> [%Step{name: :load_order, ...}, ...]
  """
  def workflow!(resource) do
    case workflow(resource) do
      {:ok, workflow} -> workflow
      :error -> raise "No workflow defined for #{inspect(resource)}"
    end
  end

  @doc """
  Returns the workflow configuration for a resource.

  Returns :error if no workflow is defined.

  ## Examples

      case AshJobs.Info.workflow(MyApp.FulfillmentJob) do
        {:ok, workflow} -> # Use workflow
        :error -> # No workflow
      end
  """
  def workflow(resource) do
    case steps(resource) do
      [] ->
        :error

      steps ->
        state_attr = state_attribute(resource)
        {:ok, %{steps: steps, state_attribute: state_attr}}
    end
  end

  @doc """
  Returns all workflow entities for a resource (both steps and parallel_steps).

  ## Examples

      entities = AshJobs.Info.steps(MyApp.FulfillmentJob)
      Enum.map(entities, & &1.name)
      #=> [:load_order, :process_parallel, :create_shipment]
  """
  def steps(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:workflow]) || []
  end

  @doc """
  Returns only regular steps (not parallel_steps) for a resource.

  ## Examples

      regular = AshJobs.Info.regular_steps(MyApp.FulfillmentJob)
      Enum.map(regular, & &1.name)
      #=> [:load_order, :create_shipment]
  """
  def regular_steps(resource) do
    steps(resource)
    |> Enum.reject(&is_parallel_step?/1)
  end

  @doc """
  Returns only parallel_steps for a resource.

  ## Examples

      parallel = AshJobs.Info.parallel_steps(MyApp.FulfillmentJob)
      Enum.map(parallel, & &1.name)
      #=> [:process_parallel]
  """
  def parallel_steps(resource) do
    steps(resource)
    |> Enum.filter(&is_parallel_step?/1)
  end

  @doc """
  Returns true if the entity is a parallel_step.
  """
  def is_parallel_step?(%AshJobs.Dsl.Entities.ParallelStep{}), do: true
  def is_parallel_step?(_), do: false

  @doc """
  Returns a specific step by name.

  ## Examples

      {:ok, step} = AshJobs.Info.step(MyApp.FulfillmentJob, :load_order)
      step.action
      #=> :load_full_order
  """
  def step(resource, step_name) do
    case Enum.find(steps(resource), &(&1.name == step_name)) do
      nil -> :error
      step -> {:ok, step}
    end
  end

  @doc """
  Returns the step that uses a given action.

  Useful for the Global Change module to determine workflow routing.
  Only searches regular steps (parallel_steps don't have actions).

  ## Examples

      {:ok, step} = AshJobs.Info.get_step_for_action(MyApp.FulfillmentJob, :load_full_order)
      step.on_success
      #=> :validate_inventory
  """
  def get_step_for_action(resource, action_name) do
    # Only search regular steps - parallel_steps don't have actions
    case Enum.find(regular_steps(resource), &(&1.action == action_name)) do
      nil -> :error
      step -> {:ok, step}
    end
  end

  @doc """
  Returns a parallel_step by name.

  ## Examples

      {:ok, parallel_step} = AshJobs.Info.get_parallel_step(MyApp.FulfillmentJob, :process_parallel)
      parallel_step.branches
      #=> [%Branch{name: :payment, resource: PaymentWorkflow}, ...]
  """
  def get_parallel_step(resource, name) do
    case Enum.find(parallel_steps(resource), &(&1.name == name)) do
      nil -> :error
      step -> {:ok, step}
    end
  end

  @doc """
  Returns the state attribute name for the workflow.

  Defaults to :state if not specified in workflow DSL.

  ## Examples

      AshJobs.Info.state_attribute(MyApp.FulfillmentJob)
      #=> :state
  """
  def state_attribute(resource) do
    Spark.Dsl.Extension.get_opt(resource, [:workflow], :state_attribute, :state)
  end

  @doc """
  Returns entry point steps (steps with no incoming references).

  Handles both regular steps and parallel_steps.

  ## Examples

      entry_points = AshJobs.Info.entry_points(MyApp.FulfillmentJob)
      Enum.map(entry_points, & &1.name)
      #=> [:load_order]
  """
  def entry_points(resource) do
    all_entities = steps(resource)
    regular = Enum.reject(all_entities, &is_parallel_step?/1)
    parallel = Enum.filter(all_entities, &is_parallel_step?/1)

    # Collect successors from regular steps
    regular_successors =
      regular
      |> Enum.flat_map(fn step -> [step.on_success, step.on_error, step.on_complete] end)

    # Collect successors from parallel steps (they have on_complete, on_error but not on_success)
    parallel_successors =
      parallel
      |> Enum.flat_map(fn step -> [step.on_complete, step.on_error] end)

    all_successors =
      (regular_successors ++ parallel_successors)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 in [:completed, :failed, :cancelled]))
      |> MapSet.new()

    Enum.reject(all_entities, fn entity -> MapSet.member?(all_successors, entity.name) end)
  end

  @doc """
  Returns terminal steps (steps that transition to terminal states).

  Terminal states: :completed, :failed, :cancelled
  Handles both regular steps and parallel_steps.

  ## Examples

      terminal_steps = AshJobs.Info.terminal_steps(MyApp.FulfillmentJob)
      Enum.map(terminal_steps, & &1.name)
      #=> [:mark_complete, :handle_error]
  """
  def terminal_steps(resource) do
    terminal_states = [:completed, :failed, :cancelled]

    steps(resource)
    |> Enum.filter(fn entity ->
      if is_parallel_step?(entity) do
        # Parallel steps have on_complete and on_error
        entity.on_complete in terminal_states or
          entity.on_error in terminal_states
      else
        # Regular steps have on_success, on_error, on_complete
        entity.on_success in terminal_states or
          entity.on_complete in terminal_states
      end
    end)
  end
end
