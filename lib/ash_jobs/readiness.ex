defmodule AshJobs.Readiness do
  @moduledoc "Runtime readiness helpers for needs-gated workflow rows."

  @type trigger_result :: :not_ready | :terminal | %Oban.Job{} | {:error, term()}

  @doc "Returns true when all configured needs have reached success terminal states."
  @spec needs_satisfied?(record :: Ash.Resource.record()) :: boolean()
  def needs_satisfied?(record) do
    case AshJobs.Info.needs_relationship(record.__struct__) do
      nil ->
        true

      relationship_name ->
        record
        |> Ash.load!([relationship_name], lazy?: false)
        |> Map.get(relationship_name, [])
        |> List.wrap()
        |> Enum.all?(&success_state?/1)
    end
  end

  @doc "Returns true when a record is non-terminal and all needs are satisfied."
  @spec ready?(record :: Ash.Resource.record()) :: boolean()
  def ready?(record) do
    not terminal_state?(record) and needs_satisfied?(record)
  end

  @doc """
  Runs an AshOban trigger only when the record is ready AND the trigger's
  generated `where` applies to the record right now.

  `AshOban.run_trigger/2` inserts the job without evaluating the trigger's
  `where` — AshOban applies that expression only in the scheduler's scan and
  the worker's re-read. Honoring it here keeps the direct paths (create-time
  first trigger, push-on-success, manual resume) as selective as the paths
  they feed: a row whose state and needs are satisfied but whose authored
  predicate is false (a parent-state gate, a custom ready flag) is not
  enqueued at all instead of being enqueued only to be cancelled by the
  worker's `where` re-read.
  """
  @spec run_trigger_if_ready(record :: Ash.Resource.record(), trigger_name :: atom()) ::
          trigger_result()
  def run_trigger_if_ready(record, trigger_name) do
    cond do
      terminal_state?(record) ->
        :terminal

      ready?(record) and where_applies?(record, trigger_name) ->
        AshOban.run_trigger(record, trigger_name)

      true ->
        :not_ready
    end
  end

  # Evaluates the trigger's `where` against the record with a bounded
  # single-row read (`exists?`), so the direct path consults the same
  # expression the scheduler and worker use — no reimplementation of the
  # predicate, no second source of truth.
  #
  # The read mirrors the generated SCHEDULER's scan semantics exactly
  # (`AshOban` `define_schedulers.ex` pipeline) — it is the pre-enqueue
  # analogue of that scan:
  #
  #   * the trigger's configured `read_action` (not a default read),
  #   * `authorize?: AshOban.authorize?()` — the same application-configured
  #     value the scheduler and worker pass (default `true`), never a
  #     hard-coded bypass,
  #   * `AshOban.build_context(trigger.shared_context)` on the query — the
  #     `%{private: %{ash_oban?: true}}` marker that `AshOban.Checks.
  #     AshObanInteraction` policies bypass on, so a policy-protected
  #     resource answers this read exactly as its own scheduler scan,
  #   * tenant from the record (mirrors `use_tenant_from_record?`),
  #     primary-key scoped to the record.
  #
  # The actor is `nil`, as it is for the generated schedulers (their Oban
  # scheduler jobs carry no actor), so authorization rests on the AshOban
  # interaction context exactly as it does for the scheduled scan.
  @spec where_applies?(record :: Ash.Resource.record(), trigger_name :: atom()) :: boolean()
  defp where_applies?(record, trigger_name) do
    case trigger_with_semantics(record.__struct__, trigger_name) do
      nil ->
        true

      {resource, trigger, domain} ->
        query =
          resource
          |> Ash.Query.select(Ash.Resource.Info.primary_key(resource))
          |> Ash.Query.set_context(AshOban.build_context(trigger.shared_context))
          |> Ash.Query.do_filter(primary_key_filter(resource, record))
          |> Ash.Query.do_filter(trigger.where)
          |> Ash.Query.for_read(trigger.read_action, %{},
            authorize?: AshOban.authorize?(),
            actor: nil,
            domain: domain
          )
          |> set_record_tenant(resource, record)

        Ash.exists?(query)
    end
  end

  defp trigger_with_semantics(resource, trigger_name) do
    case AshOban.Info.oban_trigger(resource, trigger_name) do
      nil -> nil
      trigger -> {resource, trigger, AshOban.Info.oban_domain!(resource)}
    end
  end

  defp primary_key_filter(resource, record) do
    resource
    |> Ash.Resource.Info.primary_key()
    |> Map.new(fn key -> {key, Map.get(record, key)} end)
  end

  # Attribute multitenancy: the record's tenant attribute value is the tenant
  # (mirrors AshOban's `use_tenant_from_record?`), so the read runs in the
  # record's own tenant. Resources without multitenancy (or with a nil value)
  # read tenantlessly, exactly like the generated schedulers do.
  defp set_record_tenant(query, resource, record) do
    case Ash.Resource.Info.multitenancy_attribute(resource) do
      nil ->
        query

      attribute ->
        case Map.get(record, attribute) do
          nil -> query
          tenant -> Ash.Query.set_tenant(query, tenant)
        end
    end
  end

  @doc "Runs all currently ready rows for a workflow resource once."
  @spec poll_ready(resource :: Ash.Resource.t()) :: [Ash.Resource.record()]
  def poll_ready(resource) do
    resource
    |> ready_records()
    |> Enum.map(fn record ->
      trigger_name = Map.get(record, AshJobs.Info.state_attribute(resource))
      _result = run_trigger_if_ready(record, trigger_name)
      record
    end)
  end

  @doc "Returns all currently ready rows for a workflow resource."
  @spec ready_records(resource :: Ash.Resource.t()) :: [Ash.Resource.record()]
  def ready_records(resource) do
    resource
    |> Ash.read!()
    |> Enum.filter(&ready?/1)
  end

  @doc "Pushes dependent rows that became ready after `record` reached success."
  @spec push_dependents(record :: Ash.Resource.record()) :: :ok
  def push_dependents(record) do
    resource = record.__struct__

    if AshJobs.Info.push_dependents?(resource) and success_state?(record) do
      record
      |> dependents()
      |> Enum.each(fn dependent ->
        trigger_name = Map.get(dependent, AshJobs.Info.state_attribute(dependent.__struct__))
        _result = run_trigger_if_ready(dependent, trigger_name)
      end)
    end

    :ok
  end

  @doc "Returns rows that declare `record` as a need."
  @spec dependents(record :: Ash.Resource.record()) :: [Ash.Resource.record()]
  def dependents(record) do
    case inverse_needs_relationship(record.__struct__) do
      nil ->
        []

      relationship_name ->
        record
        |> Ash.load!([relationship_name], lazy?: false)
        |> Map.get(relationship_name, [])
        |> List.wrap()
    end
  end

  @doc "Returns true when the record's current state is a success terminal state."
  @spec success_state?(record :: Ash.Resource.record()) :: boolean()
  def success_state?(record) do
    state = Map.get(record, AshJobs.Info.state_attribute(record.__struct__))
    state in AshJobs.Info.success_terminal_states(record.__struct__)
  end

  @doc "Returns true when the record's current state is terminal."
  @spec terminal_state?(record :: Ash.Resource.record()) :: boolean()
  def terminal_state?(record) do
    state = Map.get(record, AshJobs.Info.state_attribute(record.__struct__))
    state in AshJobs.Info.terminal_states(record.__struct__)
  end

  defp inverse_needs_relationship(resource) do
    needs_name = AshJobs.Info.needs_relationship(resource)
    needs = needs_name && Ash.Resource.Info.relationship(resource, needs_name)

    Enum.find_value(Ash.Resource.Info.relationships(resource), fn relationship ->
      if inverse_relationship?(relationship, needs) do
        relationship.name
      end
    end)
  end

  defp inverse_relationship?(_relationship, nil), do: false

  defp inverse_relationship?(relationship, needs) do
    relationship.type == :many_to_many and
      relationship.through == needs.through and
      relationship.source_attribute_on_join_resource ==
        needs.destination_attribute_on_join_resource and
      relationship.destination_attribute_on_join_resource ==
        needs.source_attribute_on_join_resource
  end
end
