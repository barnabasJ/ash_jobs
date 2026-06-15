defmodule AshJobs.TestResources.StaticBranchWorkflow do
  @moduledoc false
  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshJobs, AshStateMachine, AshOban]

  workflow do
    step :work do
      action(:do_work)
      on_success(:completed)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:parent_id, :uuid, public?: true)
  end

  actions do
    defaults([:read])
    create(:create, do: accept([:parent_id]))

    update :do_work do
      require_atomic?(false)
      accept([])
    end
  end
end

defmodule AshJobs.TestResources.StaticBranchRun do
  @moduledoc false
  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshJobs, AshStateMachine, AshOban]

  workflow do
    parallel_step :run_static do
      completion_strategy({:require_n, 1})
      on_complete(:completed)

      branch(:static_job, AshJobs.TestResources.StaticBranchWorkflow)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:state, :atom) do
      default(:run_static)
      allow_nil?(false)
      public?(true)
    end
  end

  actions do
    defaults([:read, :create])
  end
end

defmodule AshJobs.TestResources.DynamicRequireNRun do
  @moduledoc false
  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshJobs, AshStateMachine, AshOban]

  workflow do
    parallel_step :run_jobs do
      completion_strategy({:require_n, 5})
      on_complete(:completed)

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

    attribute(:state, :atom) do
      default(:run_jobs)
      allow_nil?(false)
      public?(true)
    end
  end

  actions do
    defaults([:read, :create])
  end
end
