defmodule AshJobs.TestResources.LongRunningWorkflow do
  @moduledoc """
  Workflow with custom step options for testing queue, timeout, and retry configuration.

  Demonstrates:
  - Custom queue names
  - Custom timeouts
  - Custom retry policies
  - Custom priorities
  """

  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban]

  postgres do
    table "long_running_workflows"
    repo(AshJobs.TestRepo)
  end

  workflow do
    triggers(true)

    step :quick_step do
      action :process_quick
      on_success(:slow_step)
      queue :fast_queue
      timeout_seconds(30)
    end

    step :slow_step do
      action :process_slow
      on_success(:retry_step)
      queue :slow_queue
      timeout_seconds(300)
    end

    step :retry_step do
      action :process_retry
      on_success(:completed)
      queue :retry_queue
      retry_attempts(5)
      retry_delay_seconds(10)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :quick_data, :string, public?: true
    attribute :slow_data, :string, public?: true
    attribute :retry_data, :string, public?: true

    attribute :state, :atom do
      default :quick_step
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name]
    end

    update :process_quick do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :quick_data, "quick_done")
      end
    end

    update :process_slow do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :slow_data, "slow_done")
      end
    end

    update :process_retry do
      require_atomic? false
      accept []

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :retry_data, "retry_done")
      end
    end
  end

  code_interface do
    define :create
    define :process_quick
    define :process_slow
    define :process_retry
    define :get_by_id, action: :read, get_by: [:id]
  end
end
