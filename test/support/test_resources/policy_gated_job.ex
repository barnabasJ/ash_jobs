defmodule AshJobs.TestResources.PolicyGatedJob do
  @moduledoc false
  use Ash.Resource,
    domain: AshJobs.TestDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJobs, AshStateMachine, AshOban],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "policy_gated_jobs"
    repo(AshJobs.TestRepo)
  end

  workflow do
    triggers(true)

    step :pending do
      action(:run)
      on_success(:completed)
      on_error(:handle_error)
      where(expr(admitted == true))
    end

    step :handle_error do
      action(:mark_failed)
      on_complete(:failed)
    end
  end

  # Only the AshOban interaction context may read this resource. The direct
  # helper must supply the same `%{private: %{ash_oban?: true}}` context the
  # generated scheduler and worker supply, or its `where` read is refused and
  # dispatch is silently withheld — the regression this fixture pins.
  policies do
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:admitted, :boolean, default: false, allow_nil?: false, public?: true)
    attribute(:run_count, :integer, default: 0, allow_nil?: false, public?: true)

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
    end

    update :run do
      require_atomic?(false)
      accept([])
      change(set_attribute(:run_count, 1))
    end

    update :mark_failed do
      require_atomic?(false)
      accept([])
    end

    update :admit do
      accept([])
      change(set_attribute(:admitted, true))
    end
  end

  code_interface do
    define(:create)
    define(:run)
    define(:admit)
    define(:get_by_id, action: :read, get_by: [:id])
  end
end
