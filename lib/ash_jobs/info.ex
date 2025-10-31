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
  Returns all workflow steps for a resource.

  ## Examples

      steps = AshJobs.Info.steps(MyApp.FulfillmentJob)
      Enum.map(steps, & &1.name)
      #=> [:load_order, :validate_inventory, :create_shipment]
  """
  def steps(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:workflow]) || []
  end

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

  ## Examples

      {:ok, step} = AshJobs.Info.get_step_for_action(MyApp.FulfillmentJob, :load_full_order)
      step.on_success
      #=> :validate_inventory
  """
  def get_step_for_action(resource, action_name) do
    case Enum.find(steps(resource), &(&1.action == action_name)) do
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
  Returns entry point steps (steps with no incoming on_success references).

  ## Examples

      entry_points = AshJobs.Info.entry_points(MyApp.FulfillmentJob)
      Enum.map(entry_points, & &1.name)
      #=> [:load_order]
  """
  def entry_points(resource) do
    all_steps = steps(resource)

    all_successors =
      all_steps
      |> Enum.flat_map(fn step -> [step.on_success, step.on_error, step.on_complete] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 in [:completed, :failed, :cancelled]))
      |> MapSet.new()

    Enum.reject(all_steps, fn step -> MapSet.member?(all_successors, step.name) end)
  end

  @doc """
  Returns terminal steps (steps that transition to terminal states).

  Terminal states: :completed, :failed, :cancelled

  ## Examples

      terminal_steps = AshJobs.Info.terminal_steps(MyApp.FulfillmentJob)
      Enum.map(terminal_steps, & &1.name)
      #=> [:mark_complete, :handle_error]
  """
  def terminal_steps(resource) do
    terminal_states = [:completed, :failed, :cancelled]

    steps(resource)
    |> Enum.filter(fn step ->
      step.on_success in terminal_states or
        step.on_complete in terminal_states
    end)
  end
end
