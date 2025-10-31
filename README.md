# AshJobs

[![Hex.pm](https://img.shields.io/hexpm/v/ash_jobs.svg)](https://hex.pm/packages/ash_jobs)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/ash_jobs)

**Declarative workflow DSL for Ash Framework** - Dramatically simplify
background job workflows by reducing boilerplate by ~75%.

AshJobs provides a declarative DSL that integrates
[ash_state_machine](https://hex.pm/packages/ash_state_machine) and
[ash_oban](https://hex.pm/packages/ash_oban), transforming complex workflow
orchestration into clean, maintainable code.

## Features

- 🎯 **Declarative DSL** - Define workflows with simple `step` blocks
- 🔄 **Automatic State Machines** - State machine DSL generated from workflow
  steps
- ⚡ **Automatic Job Scheduling** - Oban triggers created automatically
- 🛡️ **Type-Safe** - Full Ash type system integration
- 📊 **Built-in Introspection** - Query workflow status and metadata
- 🧪 **Test-Friendly** - Easy to test with Oban testing modes

## Installation

Add `ash_jobs` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_jobs, "~> 0.1.0"},
    {:ash, "~> 3.0"},
    {:ash_state_machine, "~> 0.2"},
    {:ash_oban, "~> 0.4"},
    {:oban, "~> 2.15"}
  ]
end
```

Run `mix deps.get` to install the dependencies.

## Quick Start

### 1. Define a Workflow Resource

```elixir
defmodule MyApp.Orders.FulfillmentJob do
  use Ash.Resource,
    domain: MyApp.Orders,
    extensions: [AshJobs, AshStateMachine, AshOban]

  workflow do
    # Define your workflow steps
    step :load_order do
      action :load_order_data
      on_success :validate_inventory
      on_error :handle_load_error
      queue :order_processing
    end

    step :validate_inventory do
      action :check_stock
      on_success :create_shipment
      on_error :notify_out_of_stock
      queue :inventory_processing
      retry_attempts 3
    end

    step :create_shipment do
      action :generate_shipment
      on_success :completed
      on_error :handle_shipment_error
      queue :shipping_processing
    end

    # Error handler
    step :handle_load_error do
      action :send_error_notification
      on_complete :failed
    end
  end

  # Define your attributes
  attributes do
    uuid_primary_key :id
    attribute :order_id, :uuid, allow_nil?: false
    attribute :order_items, {:array, :map}
    attribute :shipment_id, :uuid
    # State attribute generated automatically by ash_state_machine
  end

  # Define your actions with business logic
  actions do
    defaults [:read]

    create :create do
      accept [:order_id]
    end

    update :load_order_data do
      # Your business logic here
      change MyApp.Orders.Changes.LoadOrderItems
    end

    update :check_stock do
      # Your business logic here
      change MyApp.Inventory.Changes.ValidateStock
    end

    update :generate_shipment do
      # Your business logic here
      change MyApp.Shipping.Changes.CreateShipment
    end

    update :send_error_notification do
      change MyApp.Notifications.Changes.SendErrorEmail
    end
  end
end
```

### 2. Configure Oban

Add Oban to your application supervision tree:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    {Oban, Application.fetch_env!(:my_app, Oban)},
    # ... other children
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

Configure Oban in `config/config.exs`:

```elixir
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [
    default: 10,
    order_processing: 20,
    inventory_processing: 15,
    shipping_processing: 10
  ]
```

### 3. Run Migrations

Generate and run the necessary migrations:

```bash
# Generate Oban migration
mix ecto.gen.migration add_oban_jobs_table

# In the migration file:
defmodule MyApp.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 12)
  end

  def down do
    Oban.Migration.down(version: 12)
  end
end

# Run migrations
mix ecto.migrate
```

### 4. Create and Run Workflows

```elixir
# Create a new workflow job
{:ok, job} = FulfillmentJob
  |> Ash.Changeset.for_create(:create, %{order_id: order_id})
  |> Ash.create()

# The workflow will execute automatically via Oban triggers!
# Each step transitions to the next based on your on_success routing
```

## What Gets Generated

AshJobs automatically generates:

1. **State Machine DSL** - One state per step plus terminal states
   (`:completed`, `:failed`, `:cancelled`)
2. **Oban Triggers** - Automatic job scheduling for each step
3. **State Transitions** - Routing based on `on_success` and `on_error`
   configuration

### Generated State Machine (from example above)

```elixir
state_machine do
  initial_states [:load_order]
  default_initial_state :load_order

  transitions do
    transition :to_validate_inventory, from: :load_order, to: :validate_inventory
    transition :to_create_shipment, from: :validate_inventory, to: :create_shipment
    transition :to_completed, from: :create_shipment, to: :completed
    transition :to_failed, from: :handle_load_error, to: :failed
    # ... and error transitions
  end
end
```

### Generated Oban Triggers

```elixir
oban do
  triggers do
    trigger :load_order do
      action :load_order_data
      where expr(state == :load_order)
      on_error :handle_load_error
      queue :order_processing
    end
    # ... one trigger per automatic step
  end
end
```

## Workflow Introspection

Use the `AshJobs.Info` module to introspect workflows:

```elixir
# Get all workflow steps
steps = AshJobs.Info.steps(FulfillmentJob)

# Get a specific step
{:ok, step} = AshJobs.Info.step(FulfillmentJob, :validate_inventory)
step.on_success  #=> :create_shipment
step.queue       #=> :inventory_processing

# Get entry points
entry_points = AshJobs.Info.entry_points(FulfillmentJob)

# Get terminal steps
terminal_steps = AshJobs.Info.terminal_steps(FulfillmentJob)
```

## Manual Pause Points

Create manual steps that don't trigger automatically:

```elixir
step :await_user_confirmation do
  action :send_confirmation_email
  trigger false  # No automatic Oban trigger
  on_success :process_payment
end
```

Manually advance when ready:

```elixir
# When user confirms...
AshJobs.Helpers.advance_workflow(FulfillmentJob, job_id, :await_user_confirmation)
```

## Testing

AshJobs works seamlessly with Oban's testing modes:

```elixir
defmodule MyApp.FulfillmentJobTest do
  use MyApp.DataCase, async: true
  use Oban.Testing, repo: MyApp.Repo

  test "workflow executes all steps" do
    Oban.Testing.with_testing_mode(:inline) do
      {:ok, job} = FulfillmentJob.create!(%{order_id: order.id})

      # Jobs execute synchronously in inline mode
      reloaded = Ash.get!(FulfillmentJob, job.id)
      assert reloaded.state == :completed
    end
  end
end
```

## Before vs After

### Without AshJobs (~200+ lines)

```elixir
# Separate state machine definition
state_machine do
  initial_states [:load_order]
  transitions do
    transition :to_validate_inventory, from: :load_order, to: :validate_inventory
    transition :to_create_shipment, from: :validate_inventory, to: :create_shipment
    transition :to_completed, from: :create_shipment, to: :completed
    # ... many more transitions
  end
end

# Separate actions with manual routing
update :load_order_data do
  accept []
  change LoadOrderItems
  change {AshStateMachine.Transition, to: :validate_inventory}
  change {AshOban.RunObanTrigger, trigger: :validate_inventory}
end

update :check_stock do
  accept []
  change ValidateStock
  change {AshStateMachine.Transition, to: :create_shipment}
  change {AshOban.RunObanTrigger, trigger: :create_shipment}
end

# Separate Oban triggers
oban do
  triggers do
    trigger :load_order do
      action :load_order_data
      where expr(state == :load_order)
      on_error :handle_load_error
      queue :order_processing
    end

    trigger :validate_inventory do
      action :check_stock
      where expr(state == :validate_inventory)
      on_error :notify_out_of_stock
      queue :inventory_processing
    end
    # ... many more triggers
  end
end
```

### With AshJobs (~30 lines)

```elixir
workflow do
  step :load_order do
    action :load_order_data
    on_success :validate_inventory
    on_error :handle_load_error
    queue :order_processing
  end

  step :validate_inventory do
    action :check_stock
    on_success :create_shipment
    on_error :notify_out_of_stock
    queue :inventory_processing
  end

  step :create_shipment do
    action :generate_shipment
    on_success :completed
    queue :shipping_processing
  end
end

# State machine, triggers, and routing generated automatically!
```

**Result: ~75% less boilerplate code**

## Documentation

- [Full API Documentation](https://hexdocs.pm/ash_jobs)
- [AshJobs.Info](https://hexdocs.pm/ash_jobs/AshJobs.Info.html) - Workflow
  introspection
- [AshJobs.Dsl.Entities.Step](https://hexdocs.pm/ash_jobs/AshJobs.Dsl.Entities.Step.html) -
  Step configuration options

## Requirements

- Elixir ~> 1.14
- Ash ~> 3.0
- AshStateMachine ~> 0.2
- AshOban ~> 0.4
- Oban ~> 2.15
- PostgreSQL (required by Oban)

## License

Copyright © 2025

Licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please read our
[contributing guidelines](CONTRIBUTING.md) before submitting pull requests.

## Acknowledgments

AshJobs builds on the excellent work of:

- [Ash Framework](https://ash-hq.org) by Zach Daniel
- [ash_state_machine](https://github.com/ash-project/ash_state_machine)
- [ash_oban](https://github.com/ash-project/ash_oban)
- [Oban](https://getoban.pro) by Parker Selbert
