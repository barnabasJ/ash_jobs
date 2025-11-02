# AshJobs Project Status

**Last Updated:** 2025-11-02 **Status:** Core workflow engine complete and fully
tested (89 tests passing)

## Overview

AshJobs is an Elixir library that integrates Ash Framework with Oban for
declarative, stateful background job workflows. The library allows developers to
define multi-step workflows with automatic state management, error handling, and
Oban job scheduling.

## What's Implemented ✅

### Core Workflow Engine

1. **Workflow DSL** (`lib/ash_jobs/dsl.ex`)

   - Declarative step definition with routing options
   - Support for: `action`, `on_success`, `on_error`, `on_complete`, `queue`,
     `retry_attempts`, `timeout_seconds`
   - Error handler steps and terminal states

2. **Automatic Workflow Routing** (`lib/ash_jobs/change.ex`)

   - Global change module injected into all workflow actions
   - **Create actions**: Automatically trigger initial workflow step
   - **Workflow steps**: Transition state and trigger next step
   - Uses `AshOban.run_trigger` for automatic job scheduling
   - No manual scheduling required - just create a job!

3. **AshStateMachine Integration**
   (`lib/ash_jobs/transformers/integrate_state_machine.ex`)

   - Auto-generates state machine configuration from workflow steps
   - Creates transitions based on `on_success` and `on_complete`
   - Manages state constraints and validation
   - Handles initial/terminal states

4. **AshOban Integration** (`lib/ash_jobs/transformers/integrate_oban.ex`)

   - Auto-generates Oban triggers for each workflow step
   - Configures queues, retries, timeouts per step
   - Generates proper worker/scheduler module names
   - Links error handlers via `on_error` trigger option

5. **Error Handling** (`lib/ash_jobs/transformers/generate_error_actions.ex`)

   - Auto-generates error handler actions
   - Accepts error argument with job failure details
   - Routes to terminal states via `on_complete`

6. **Workflow Introspection** (`lib/ash_jobs/info.ex`)
   - `workflow/1` - Get workflow configuration
   - `steps/1` - List all workflow steps
   - `entry_points/1` - Find initial steps
   - `terminal_steps/1` - Find steps leading to terminal states
   - `step/2` - Get specific step configuration
   - `get_step_for_action/2` - Map actions to steps

### Test Infrastructure

- **Integration Tests**: 23 tests covering full workflow execution via Oban
- **Unit Tests**: 66 tests for transformers, verifiers, and DSL
- **Test Database**: Full Postgres setup with Ecto migrations
- **Oban Testing**: Manual mode with queue draining for deterministic tests
- **Ecto Sandbox**: Concurrent test isolation

## How It Works

### Workflow Execution Flow

```elixir
# 1. Define a workflow resource
defmodule OrderFulfillmentJob do
  use Ash.Resource,
    extensions: [AshJobs, AshStateMachine, AshOban]

  workflow do
    step :load_order do
      action :load_order_data
      on_success :validate_inventory
      on_error :handle_load_error
      queue :orders
    end

    step :validate_inventory do
      action :check_inventory
      on_success :create_shipment
      on_error :handle_inventory_error
      queue :inventory
    end

    step :create_shipment do
      action :generate_shipment
      on_success :completed
      queue :shipping
    end

    step :handle_load_error do
      action :notify_load_error
      on_complete :failed
    end
  end

  attributes do
    attribute :state, :atom, default: :load_order
    # ... other attributes
  end

  actions do
    create :create
    update :load_order_data
    update :check_inventory
    update :generate_shipment
    # Error handler action auto-generated!
  end
end

# 2. Create a job - workflow starts automatically!
{:ok, job} = OrderFulfillmentJob.create(%{order_id: "123"})
# State: :load_order
# Oban job scheduled for :load_order step

# 3. Oban processes the job
# -> Executes :load_order_data action
# -> Change module transitions state to :validate_inventory
# -> Change module triggers :validate_inventory step
# -> Oban job scheduled for :validate_inventory step

# 4. Process continues automatically
# :validate_inventory -> :create_shipment -> :completed

# 5. Final state
job = Repo.get!(OrderFulfillmentJob, job.id)
job.state # => :completed
```

### Key Components

**Transformers (compile-time):**

1. `GenerateErrorActions` - Creates error handler actions
2. `BuildWorkflow` - Injects Change module into actions
3. `IntegrateStateMachine` - Generates state machine config
4. `IntegrateOban` - Generates Oban triggers
5. `ValidateWorkflow` - Validates workflow configuration

**Runtime:**

1. `AshJobs.Change` - Handles state transitions and job triggering
2. `AshOban` - Schedules and executes jobs
3. `AshStateMachine` - Validates state transitions

## Testing

### Run All Tests

```bash
mix test
# 89 tests, 0 failures
```

### Integration Tests Only

```bash
mix test test/integration/
# 23 tests covering workflow execution
```

### Test Database Setup

```bash
# First time setup
mix test.setup

# Reset database
mix test.reset
```

### Test Pattern

```elixir
# Create job (auto-triggers workflow)
{:ok, job} = OrderFulfillmentJob.create(%{order_id: "TEST-001"})

# Drain Oban queues to execute jobs (2 drains per step: scheduler + worker)
Oban.drain_queue(queue: :orders)
Oban.drain_queue(queue: :orders)

# Verify state changed
job = TestRepo.get!(OrderFulfillmentJob, job.id)
assert job.state == :validate_inventory
```

## What's NOT Implemented ❌

### Missing Features

1. **Conditional Routing**

   - No support for dynamic routing based on data
   - All routing is static (defined at compile time)

2. **Parallel Steps**

   - No support for parallel/concurrent step execution
   - Workflow is strictly sequential

3. **Manual Step Triggers**

   - All automatic steps must have `trigger: true`
   - Manual trigger support exists but not well tested

4. **Workflow Pause/Resume**

   - No built-in support for pausing workflows
   - No workflow scheduling (e.g., run at specific time)

5. **Workflow Cancellation**

   - No helper for cancelling in-progress workflows
   - Would need to manually transition to `:cancelled` state

6. **Retry Configuration**

   - Retry attempts configured per step, not per job
   - No exponential backoff support (uses Oban defaults)

7. **Telemetry Events**

   - Change module has telemetry placeholders but not implemented
   - No workflow-level events (start, complete, fail)

8. **Workflow Versioning**
   - No support for migrating workflows when definitions change
   - Changing workflow DSL requires data migration

## Known Issues / Limitations

1. **Error Handler Actions**

   - Must be manually defined in actions block
   - Auto-generated actions are minimal (just error arg + state change)
   - No built-in notification/logging functionality

2. **State Attribute**

   - Must be an atom type
   - Cannot use custom state types
   - State attribute name configurable via `state_attribute` option

3. **Trigger Module Names**

   - Auto-generated names use pattern: `Resource.AshOban.Worker.StepName`
   - Cannot customize module naming scheme
   - Module names must be unique across all triggers

4. **Create Action Behavior**
   - ALL create actions trigger workflow (if resource has workflow)
   - Cannot have create actions that don't trigger workflow
   - Workaround: Use `trigger: false` on first step (but this disables automatic
     triggering)

## Architecture Decisions

### Why Change Module Instead of Global Changes Block?

Ash doesn't have a global changes block - changes are action-specific. The
`BuildWorkflow` transformer injects the `AshJobs.Change` module into individual
actions.

### Why Auto-Trigger on Create?

Users expect workflow jobs to start automatically when created. Manual
scheduling adds friction and is easy to forget. The auto-trigger pattern matches
user expectations: "create a job and it runs."

### Why Both on_success AND on_complete?

- `on_success`: Normal workflow progression (step succeeded)
- `on_complete`: Terminal routing (e.g., error handlers always go to `:failed`)
- This distinction allows error handlers to always reach terminal state

### Why Separate Error Handler Steps?

Error handlers are workflow steps that:

1. Accept error details as argument
2. Can perform cleanup/notification logic
3. Always transition to terminal state via `on_complete`

This is more flexible than automatic error routing and allows custom error
handling logic.

### Why Two Oban Queue Drains Per Step in Tests?

AshOban uses a two-stage process:

1. **Scheduler job**: Checks trigger condition, creates worker job
2. **Worker job**: Executes the actual action

Tests must drain twice to execute both stages.

## File Structure

```
ash_jobs/
├── lib/
│   ├── ash_jobs.ex                          # Main extension module
│   ├── ash_jobs/
│   │   ├── change.ex                        # Workflow routing change module
│   │   ├── dsl.ex                           # Workflow DSL definition
│   │   ├── info.ex                          # Workflow introspection functions
│   │   ├── transformers/
│   │   │   ├── build_workflow.ex            # Injects Change module
│   │   │   ├── generate_error_actions.ex    # Creates error handlers
│   │   │   ├── integrate_oban.ex            # Generates Oban triggers
│   │   │   └── integrate_state_machine.ex   # Generates state machine config
│   │   └── verifiers/
│   │       └── validate_workflow.ex         # Validates workflow definition
├── test/
│   ├── integration/
│   │   └── workflow_execution_test.exs      # End-to-end workflow tests (23 tests)
│   ├── support/
│   │   ├── test_domain.ex                   # Test Ash domain
│   │   ├── test_repo.ex                     # Test Ecto repo
│   │   └── test_resources/
│   │       └── order_fulfillment_job.ex     # Test workflow resource
│   ├── ash_jobs/
│   │   ├── transformers/                    # Transformer unit tests
│   │   └── verifiers/                       # Verifier unit tests
│   └── test_helper.exs                      # Test setup + Oban start
├── config/
│   ├── config.exs                           # Import test config
│   └── test.exs                             # Oban test configuration
└── priv/
    └── test_repo/
        └── migrations/                      # Test database migrations
```

## Next Steps / TODO

### High Priority

1. **Documentation**

   - [ ] Add comprehensive README with examples
   - [ ] Document all DSL options
   - [ ] Add HexDocs documentation
   - [ ] Create getting started guide

2. **Error Handler Improvements**

   - [ ] Add built-in logging to error handlers
   - [ ] Support custom error handler logic
   - [ ] Add error details to workflow introspection

3. **Telemetry**
   - [ ] Implement workflow lifecycle events
   - [ ] Add step execution metrics
   - [ ] Add error tracking events

### Medium Priority

4. **Conditional Routing**

   - [ ] Support for dynamic routing based on data
   - [ ] Add conditional step execution

5. **Workflow Helpers**

   - [ ] Add `cancel_workflow/1` helper
   - [ ] Add `retry_workflow/1` helper
   - [ ] Add workflow status queries

6. **Testing Improvements**
   - [ ] Add more error scenario tests
   - [ ] Test workflow versioning scenarios
   - [ ] Add performance/load tests

### Low Priority

7. **Advanced Features**
   - [ ] Parallel step execution
   - [ ] Workflow scheduling
   - [ ] Workflow pause/resume
   - [ ] Workflow versioning/migration

## Getting Started (for new developers)

### Prerequisites

- Elixir 1.18+
- PostgreSQL (for testing)

### Setup

```bash
# Clone and setup
cd ash_jobs
mix deps.get

# Setup test database
mix test.setup

# Run tests
mix test
```

### Making Changes

1. **Understand the transformer chain** - Changes often require updates to
   multiple transformers
2. **Update tests** - Both unit tests (transformer) and integration tests
   (workflow execution)
3. **Check test coverage** - All 89 tests should pass
4. **Follow commit pattern** - Logical commits with detailed messages

### Key Files to Read First

1. `lib/ash_jobs/dsl.ex` - Understand the workflow DSL
2. `lib/ash_jobs/change.ex` - Understand runtime routing
3. `test/integration/workflow_execution_test.exs` - See complete examples
4. `test/support/test_resources/order_fulfillment_job.ex` - Example workflow

### Common Tasks

**Add new workflow option:**

1. Update DSL definition in `lib/ash_jobs/dsl.ex`
2. Update relevant transformer to use the option
3. Add test case
4. Update verifier if validation needed

**Fix transformer bug:**

1. Add failing test first
2. Fix transformer
3. Verify all tests pass
4. Check integration tests still work

**Add new feature:**

1. Design DSL API first
2. Update transformers
3. Update Change module if needed
4. Add integration test
5. Update documentation

## Contact / Questions

For questions about the codebase, refer to:

- Integration tests for usage examples
- Transformer code for DSL processing
- Change module for runtime behavior
- This document for architecture decisions

---

**Remember:** The workflow engine is fully functional. The foundation is solid.
Focus on documentation, error handling, and developer experience improvements.
