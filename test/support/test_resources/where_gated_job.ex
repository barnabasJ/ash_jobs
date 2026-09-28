defmodule AshJobs.TestResources.WhereGatedJob do
  @moduledoc false
  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "where_gated_jobs"
    repo(AshJobs.TestRepo)
  end

  workflow do
    triggers(true)

    step :pending do
      action(:run)
      on_success(:completed)
      on_error(:handle_error)

      # The gate under test for the direct (create/push) enqueue path: a row
      # whose `admitted` flag is false must not be enqueued by
      # `AshJobs.Readiness.run_trigger_if_ready/2`, exactly as the generated
      # scheduler and worker already exclude it.
      where(expr(admitted == true))
    end

    step :handle_error do
      action(:mark_failed)
      on_complete(:failed)
    end
  end

  relationships do
    many_to_many(:needs, __MODULE__) do
      through(AshJobs.TestResources.WhereGatedNeed)
      source_attribute_on_join_resource(:dependent_id)
      destination_attribute_on_join_resource(:need_id)
      public?(true)
    end

    many_to_many(:dependents, __MODULE__) do
      through(AshJobs.TestResources.WhereGatedNeed)
      source_attribute_on_join_resource(:need_id)
      destination_attribute_on_join_resource(:dependent_id)
      public?(true)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:admitted, :boolean, default: false, allow_nil?: false, public?: true)
    attribute(:run_count, :integer, default: 0, allow_nil?: false, public?: true)
    attribute(:started_at, :utc_datetime_usec, public?: true)
    attribute(:completed_at, :utc_datetime_usec, public?: true)

    attribute(:state, :atom) do
      default(:pending)
      allow_nil?(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  actions do
    defaults([:read])

    create :create do
      accept([:name, :admitted])
      argument(:need_ids, {:array, :uuid}, allow_nil?: false, default: [])
      change(manage_relationship(:need_ids, :needs, type: :append_and_remove))
    end

    update :run do
      require_atomic?(false)
      accept([])
      change(AshJobs.TestChanges.MarkDagJobRun)
    end

    update :mark_failed do
      require_atomic?(false)
      accept([])
    end

    # Opens the custom gate on a `:pending` row. Deliberately NOT a workflow
    # step action, so no AshJobs routing change fires and no trigger runs —
    # the test controls enqueueing explicitly through `run_trigger_if_ready`.
    update :admit do
      accept([])
      change(set_attribute(:admitted, true))
    end
  end

  code_interface do
    define(:create)
    define(:run)
    define(:admit)
    define(:mark_failed)
    define(:get_by_id, action: :read, get_by: [:id])
  end
end

defmodule AshJobs.TestResources.WhereGatedNeed do
  @moduledoc false
  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "where_gated_needs"
    repo(AshJobs.TestRepo)
  end

  relationships do
    belongs_to(:dependent, AshJobs.TestResources.WhereGatedJob,
      source_attribute: :dependent_id,
      allow_nil?: false,
      public?: true
    )

    belongs_to(:need, AshJobs.TestResources.WhereGatedJob,
      source_attribute: :need_id,
      allow_nil?: false,
      public?: true
    )
  end

  attributes do
    uuid_primary_key(:id)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:dependent_id, :need_id])
    end
  end

  code_interface do
    define(:create)
  end
end
