defmodule AshJobs.TestResources.DagRun do
  @moduledoc false
  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "dag_runs"
    repo(AshJobs.TestRepo)
  end

  workflow do
    triggers(true)

    parallel_step :run_jobs do
      completion_strategy(:all)
      on_complete(:completed)
      on_error(:failed)

      branch(:jobs, relationship: :jobs, needs: :needs)
    end
  end

  relationships do
    has_many(:jobs, AshJobs.TestResources.DagJob,
      destination_attribute: :parent_id,
      public?: true
    )
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:error_message, :string, public?: true)

    attribute(:state, :atom) do
      default(:run_jobs)
      allow_nil?(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  actions do
    defaults([:read])

    create :create do
      accept([:name])
    end

    update :fail_cycle do
      require_atomic?(false)
      accept([])
    end
  end

  code_interface do
    define(:create)
    define(:get_by_id, action: :read, get_by: [:id])
  end
end

defmodule AshJobs.TestResources.DagNeed do
  @moduledoc false
  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "dag_needs"
    repo(AshJobs.TestRepo)
  end

  relationships do
    belongs_to(:dependent, AshJobs.TestResources.DagJob,
      source_attribute: :dependent_id,
      allow_nil?: false,
      public?: true
    )

    belongs_to(:need, AshJobs.TestResources.DagJob,
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

defmodule AshJobs.TestResources.DagJob do
  @moduledoc false
  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "dag_jobs"
    repo(AshJobs.TestRepo)
  end

  workflow do
    triggers(true)
    needs(:needs)

    step :pending do
      action(:run)
      on_success(:completed)
      on_error(:handle_error)
    end

    step :handle_error do
      action(:mark_failed)
      on_complete(:failed)
    end

    # Manual cancel from the pending state: cancelling a row drives it to the
    # non-success `:cancelled` terminal, which skips its downstream dependents.
    step :cancel do
      from(:pending)
      action(:cancel)
      on_complete(:cancelled)
      trigger(false)
    end
  end

  relationships do
    many_to_many(:needs, AshJobs.TestResources.DagJob) do
      through(AshJobs.TestResources.DagNeed)
      source_attribute_on_join_resource(:dependent_id)
      destination_attribute_on_join_resource(:need_id)
      public?(true)
    end

    many_to_many(:dependents, AshJobs.TestResources.DagJob) do
      through(AshJobs.TestResources.DagNeed)
      source_attribute_on_join_resource(:need_id)
      destination_attribute_on_join_resource(:dependent_id)
      public?(true)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:parent_id, :uuid, allow_nil?: false, public?: true)
    attribute(:name, :string, allow_nil?: false, public?: true)
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
      accept([:parent_id, :name])
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

    update :cancel do
      require_atomic?(false)
      accept([])
    end

    update :skip do
      require_atomic?(false)
      accept([])
    end
  end

  code_interface do
    define(:create)
    define(:run)
    define(:mark_failed)
    define(:cancel)
    define(:get_by_id, action: :read, get_by: [:id])
  end
end

defmodule AshJobs.TestResources.PollingDagNeed do
  @moduledoc false
  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "polling_dag_needs"
    repo(AshJobs.TestRepo)
  end

  relationships do
    belongs_to(:dependent, AshJobs.TestResources.PollingDagJob,
      source_attribute: :dependent_id,
      allow_nil?: false,
      public?: true
    )

    belongs_to(:need, AshJobs.TestResources.PollingDagJob,
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

defmodule AshJobs.TestResources.PollingDagJob do
  @moduledoc false
  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "polling_dag_jobs"
    repo(AshJobs.TestRepo)
  end

  workflow do
    triggers(true)
    needs(:needs)
    push_dependents(false)

    step :pending do
      action(:run)
      on_success(:completed)
    end
  end

  relationships do
    many_to_many(:needs, AshJobs.TestResources.PollingDagJob) do
      through(AshJobs.TestResources.PollingDagNeed)
      source_attribute_on_join_resource(:dependent_id)
      destination_attribute_on_join_resource(:need_id)
      public?(true)
    end

    many_to_many(:dependents, AshJobs.TestResources.PollingDagJob) do
      through(AshJobs.TestResources.PollingDagNeed)
      source_attribute_on_join_resource(:need_id)
      destination_attribute_on_join_resource(:dependent_id)
      public?(true)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
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
      accept([:name])
      argument(:need_ids, {:array, :uuid}, allow_nil?: false, default: [])
      change(manage_relationship(:need_ids, :needs, type: :append_and_remove))
    end

    update :run do
      require_atomic?(false)
      accept([])
      change(AshJobs.TestChanges.MarkDagJobRun)
    end

    update :skip do
      require_atomic?(false)
      accept([])
    end
  end

  code_interface do
    define(:create)
    define(:run)
    define(:get_by_id, action: :read, get_by: [:id])
  end
end
