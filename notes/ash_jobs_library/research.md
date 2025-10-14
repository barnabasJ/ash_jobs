# AshJobs Library - Codebase Impact Analysis & Research

**Topic:** Building ash_jobs library with state machine DSL and Oban integration

**Date:** 2025-10-13

---

## Executive Summary

This research phase analyzes the requirements for building `ash_jobs`, an Ash
extension that combines ash_state_machine and ash_oban to provide a sequential
workflow DSL. The library generates workflow state attributes and adds routing
logic to user-defined actions via a global Change module.

**Key Findings:**

- Project is greenfield - no dependencies currently installed
- Must integrate three major Ash ecosystem libraries: ash_state_machine,
  ash_oban, and workflow patterns
- Requires sophisticated DSL design using Spark.Dsl.Extension
- **Sequential execution**: Steps run one at a time via explicit
  `on_success`/`on_error` routing
- **State-based orchestration**: Oban triggers filter on current step state
- **User-defined actions**: Users write all business logic in normal Ash actions
- **Global Change module**: Single Change module handles routing after user's
  logic completes
- **No executor actions**: Simplified architecture - no special processing
  functions generated
- **Regular attributes**: Workflow state stored in normal Ash attributes (no
  special context management)
- **Manual pause points**: Workflows can wait for external input (user
  confirmations, webhooks)
- **Single-resource workflows**: All steps call actions on the same resource

---

## 1. Project Dependencies Discovered

### Current State (mix.exs:22-27)

```elixir
defp deps do
  [
    # No dependencies currently installed
  ]
end
```

### Required Dependencies to Add

**Core Ash Framework:**

- `ash` ~> 3.0 - Core Ash framework
- `spark` ~> 2.0 - DSL framework underlying Ash

**State Management & Job Execution:**

- `ash_state_machine` ~> 0.2.12 - State machine extension for Ash resources
  - 📖
    [ash_state_machine Getting Started](https://hexdocs.pm/ash_state_machine/getting-started-with-ash-state-machine.html)
  - 📖
    [ash_state_machine GitHub](https://github.com/ash-project/ash_state_machine)
- `ash_oban` ~> 0.4.12 - Background job integration with Oban
  - 📖
    [ash_oban Getting Started](https://hexdocs.pm/ash_oban/getting-started-with-ash-oban.html)
  - 📖 [ash_oban GitHub](https://github.com/ash-project/ash_oban)
- `oban` ~> 2.15 - Required peer dependency for ash_oban
  - 📖 [Oban Documentation](https://hexdocs.pm/oban/Oban.html)

**Workflow Orchestration:**

- `reactor` ~> 0.17.0 - Saga orchestration framework (optional, for patterns)
  - 📖 [Reactor Documentation](https://hexdocs.pm/reactor/readme.html)
  - Note: Ash includes Ash.Reactor built-in, external reactor is for pattern
    reference

**Development & Testing:**

- `ex_doc` ~> 0.31 - Documentation generation
- `credo` ~> 1.7 - Code quality analysis
- `dialyxir` ~> 1.4 - Type checking via Dialyzer

### Testing Framework

- Currently uses: ExUnit (Elixir built-in)
- Test pattern: Standard ExUnit with doctest support
- Found in: `test/test_helper.exs:1`, `test/ash_jobs_test.exs:2`

---

## 2. Files Requiring Changes

### New Files to Create

**Core Extension Module:**

- `lib/ash_jobs.ex` (REPLACE EXISTING) - Main extension definition with
  Spark.Dsl.Extension
  - 📖 [Spark.Dsl.Extension](https://hexdocs.pm/spark/Spark.Dsl.Extension.html)
  - 📖
    [Writing Extensions Guide](https://hexdocs.pm/ash/writing-extensions.html)

**DSL Definition Modules:**

- `lib/ash_jobs/dsl/workflow.ex` - Workflow entity definition
  - Define workflow DSL structure (name, steps, error handling)
- `lib/ash_jobs/dsl/step.ex` - Step entity within workflows
  - Define individual step configuration (action name, timeouts, routing)
  - Support manual (pausable) and automatic (Oban-triggered) steps via `trigger`
    option
  - Custom state names via `state` option (overrides default generated name)
  - Explicit routing via `on_success`, `on_error`, `on_complete`
  - All steps call actions on the current resource only
- `lib/ash_jobs/dsl/sections.ex` - DSL section definitions
  - Create `:workflows` top-level section

**Transformer Modules:**

- `lib/ash_jobs/transformers/validate_workflow.ex` - Workflow consistency
  validation
  - Validate step references, circular dependencies, state machine compatibility
- `lib/ash_jobs/transformers/resolve_conflicts.ex` - Handle pre-existing
  declarations
  - Validate existing attribute types (fail only on type mismatch)
  - Skip generation if correct type already exists
  - Verify user-defined actions exist
- `lib/ash_jobs/transformers/build_workflow.ex` - Main code generation
  transformer
  - Generate attributes, actions, state machine transitions, Oban triggers
  - 📖
    [Spark.Dsl.Transformer](https://hexdocs.pm/spark/Spark.Dsl.Transformer.html)
- `lib/ash_jobs/transformers/integrate_state_machine.ex` - State machine setup
  - Configure ash_state_machine transitions for workflow steps
- `lib/ash_jobs/transformers/integrate_oban.ex` - Oban trigger setup
  - Configure ash_oban triggers for step execution

**Change Module (Core Execution Logic):**

- `lib/ash_jobs/change.ex` - Global Change module
  - Single Change that intercepts all workflow action executions
  - Handles state transitions based on `on_success`/`on_error` routing
  - Merges step outputs into workflow attributes
  - Triggers next Oban job via `run_oban_trigger`
  - No modification to user's action logic - runs after user's changes
  - 📖 [Ash.Resource.Change](https://hexdocs.pm/ash/Ash.Resource.Change.html)

**Introspection & Helpers:**

- `lib/ash_jobs/info.ex` - Runtime introspection module
  - Use Spark.InfoGenerator to expose workflow configuration
  - 📖 [Spark.InfoGenerator](https://hexdocs.pm/spark/Spark.InfoGenerator.html)
- `lib/ash_jobs/helpers.ex` - Helper functions for workflow management
  - Utility functions for querying workflow state
  - Functions to manually advance workflows (for manual pause points)

**Optional Extensibility:**

- `lib/ash_jobs/workflow_handler.ex` - Behaviour for custom workflow hooks
  - Allow users to implement before_step, after_step, on_complete callbacks

### Test Files to Create

**Unit Tests:**

- `test/ash_jobs/dsl_test.exs` - DSL parsing and validation tests
- `test/ash_jobs/transformers_test.exs` - Transformer behavior tests
- `test/ash_jobs/conflict_resolution_test.exs` - Pre-existing declaration
  handling
- `test/ash_jobs/change_test.exs` - Global Change module behavior tests
- `test/ash_jobs/manual_step_test.exs` - Manual pause point tests
- `test/ash_jobs/routing_test.exs` - on_success/on_error routing tests

**Integration Tests:**

- `test/ash_jobs/workflow_execution_test.exs` - End-to-end workflow tests
- `test/ash_jobs/state_machine_integration_test.exs` - State machine integration
- `test/ash_jobs/oban_integration_test.exs` - Oban trigger tests
- `test/ash_jobs/error_handling_test.exs` - Failure and retry scenarios
- `test/ash_jobs/manual_trigger_test.exs` - Manual step advancement tests

**Test Support:**

- `test/support/test_resource.ex` - Sample resource for testing
- `test/support/test_api.ex` - Sample API for integration tests

---

## 3. Existing Patterns Found

### Current Project State

**No established patterns yet** - This is a greenfield project with only
boilerplate:

- Single module: `lib/ash_jobs.ex:1-18` (hello world stub)
- Single test: `test/ash_jobs_test.exs:1-8` (hello world test)

### Patterns to Establish (Based on Ash Ecosystem Standards)

**Extension Architecture Pattern:**

```elixir
defmodule AshJobs do
  use Spark.Dsl.Extension,
    transformers: [
      AshJobs.Transformers.ValidateWorkflow,
      AshJobs.Transformers.ResolveConflicts,
      AshJobs.Transformers.BuildWorkflow,
      AshJobs.Transformers.IntegrateStateMachine,
      AshJobs.Transformers.IntegrateOban
    ],
    sections: [AshJobs.Dsl.Sections.workflows()],
    verifiers: [AshJobs.Verifiers.WorkflowConsistency]
end
```

**DSL Usage Pattern (What Users Will Write):**

**Architectural Pattern: Separate Job Resources**

The recommended pattern is to create separate job resources for each workflow
type, rather than putting multiple workflows on a single domain resource. This
aligns with ash_state_machine's one-state-machine-per-resource design.

```elixir
# Domain entity - just business data
defmodule MyApp.Orders.Order do
  use Ash.Resource

  attributes do
    attribute :customer_id, :uuid
    attribute :order_total, :decimal
    attribute :items, {:array, :map}
    attribute :status, :atom  # High-level status: :pending, :processing, :completed
  end

  relationships do
    has_many :fulfillment_jobs, MyApp.Orders.FulfillmentJob
  end
end

# Workflow resource - one workflow per resource
defmodule MyApp.Orders.FulfillmentJob do
  use Ash.Resource,
    extensions: [AshJobs, AshStateMachine, AshOban]

  workflow do
    # Optional: override state attribute (defaults to :state)
    state_attribute :state

    # Steps execute sequentially via explicit routing
    # User defines their own actions - AshJobs just adds routing logic

    step :load_order do
      action :load_full_order  # User's action (defined below)

      # Explicit next step routing
      on_success :validate_inventory
      on_error :handle_load_error

      queue :order_processing
    end

    step :validate_inventory do
      action :check_inventory  # User's action

      on_success :calculate_total
      on_error :notify_inventory_error

      queue :inventory_processing
      timeout_seconds 30
    end

    step :calculate_total do
      action :calculate_order_total  # User's action

      on_success :charge_payment
      on_error :handle_calculation_error
    end

    step :charge_payment do
      action :create_charge  # User's action (calls Payment API internally)

      on_success :await_user_confirmation
      on_error :handle_payment_failure

      queue :payment_processing
      retry_attempts 3
      retry_delay_seconds 60
    end

    # Manual pause point - waits for external completion (e.g., user confirmation)
    step :await_user_confirmation do
      action :send_confirmation_request
      trigger false  # No Oban trigger - must be manually advanced

      on_success :create_shipment
      on_error :handle_confirmation_timeout
    end

    step :create_shipment do
      action :create_shipment  # User's action (calls Shipment API internally)

      on_success :send_confirmation
      on_error :refund_and_notify

      queue :shipping_processing
    end

    step :send_confirmation do
      action :send_order_email  # User's action

      on_success :mark_complete
      on_error :mark_complete  # Still complete even if email fails

      queue :notifications
    end

    step :mark_complete do
      action :mark_as_complete  # User's action

      on_success :completed  # Terminal state
    end

    # Error handling steps
    step :handle_payment_failure do
      action :notify_payment_failed  # User's action

      on_complete :failed  # Terminal state
    end

    step :notify_inventory_error do
      action :send_inventory_error  # User's action
      on_complete :failed
    end

    step :refund_and_notify do
      action :refund_payment  # User's action
      on_complete :failed
    end
  end

  # Workflow state attributes (generated by AshJobs)
  # - state: Current step in workflow (defaults to :state, overridable)
  # - started_at: When workflow started
  # - completed_at: When workflow completed
  # - last_error: Last error message if any

  attributes do
    # User's custom attributes for passing data between steps
    attribute :order_items, {:array, :map}
    attribute :order_total, :decimal
    attribute :payment_receipt_id, :string
    attribute :shipment_id, :uuid
  end

  relationships do
    belongs_to :order, MyApp.Orders.Order
  end

  actions do
    # User defines their own actions - business logic only
    # AshJobs automatically adds the global Change module to handle routing

    update :load_full_order do
      # User's business logic
      change LoadOrderItems
      # AshJobs automatically adds: change AshJobs.Change (for routing)
    end

    update :calculate_order_total do
      # User's business logic
      change CalculateTotal
      # AshJobs automatically adds: change AshJobs.Change (for routing)
    end

    update :mark_as_complete do
      # User's business logic
      change fn changeset, _ ->
        Ash.Changeset.change_attribute(changeset, :status, :completed)
      end
      # AshJobs automatically adds: change AshJobs.Change (for routing)
    end
  end
end

# To start a workflow:
FulfillmentJob.create!(%{order_id: order.id, state: :load_order})
```

**Execution Flow (Sequential with Explicit Routing):**

1. **load_order** runs first (initial step)
2. **validate_inventory** runs after load_order succeeds
3. **calculate_total** runs after validate_inventory succeeds
4. **charge_payment** runs after calculate_total succeeds
5. **create_shipment** runs after charge_payment succeeds
6. **send_confirmation** runs after create_shipment succeeds
7. **mark_complete** runs after send_confirmation (completes or fails)
8. If any step fails, control passes to its `on_error` handler

**Note:** Execution is **sequential** - one step at a time. Control flow is
**explicit** via `on_success`/`on_error`. Data flows through typed context map.

---

## 4. Integration Points

### External Dependencies Integration

**ash_state_machine Integration:**

- **Purpose:** Track current workflow step for Oban trigger filtering
- **Integration Method:** State machine with one state per step
- **Architectural Note:** Since ash_state_machine only supports one state
  machine per resource, the recommended pattern is to use separate job resources
  (e.g., `FulfillmentJob`, `ReturnJob`) rather than multiple workflows on one
  resource
- **Generated Entities:**
  - State attribute: `:state` (default, overridable via `state_attribute`
    option)
  - Each step becomes a state in the state machine
  - Terminal states: `:completed`, `:failed`, `:cancelled`
- **Example Generation:**

  ```elixir
  # In FulfillmentJob resource
  state_machine do
    initial_states [:load_order]
    default_initial_state :load_order
    state_attribute :state  # Simple, matches ash_state_machine convention

    transitions do
      # Generated from on_success/on_error routing
      transition :to_validate_inventory, from: :load_order, to: :validate_inventory
      transition :to_calculate_total, from: :validate_inventory, to: :calculate_total
      transition :to_charge_payment, from: :calculate_total, to: :charge_payment
      transition :to_create_shipment, from: :charge_payment, to: :create_shipment
      transition :to_send_confirmation, from: :create_shipment, to: :send_confirmation
      transition :to_mark_complete, from: :send_confirmation, to: :mark_complete
      transition :to_completed, from: :mark_complete, to: :completed

      # Error transitions
      transition :to_handle_payment_failure, from: :charge_payment, to: :handle_payment_failure
      transition :to_failed, from: :handle_payment_failure, to: :failed
    end
  end
  ```

- 📖
  [AshStateMachine DSL Reference](https://hexdocs.pm/ash_state_machine/dsl-ashstatemachine.html)

**ash_oban Integration:**

- **Purpose:** Background job execution for each workflow step
- **Integration Method:** Transformer adds one Oban trigger per step
- **Generated Entities:**
  - One trigger per automatic step (steps with `trigger: false` are skipped)
  - Each trigger filters on its specific step state
  - Triggers call user's actions directly
  - Global Change module handles routing after action completes
- **Manual Pause Points:** Steps with `trigger false` don't get Oban triggers
  - Must be advanced manually by calling the action directly
  - Used for external confirmations, webhooks, user input, etc.
  - Still use `on_success`/`on_error` routing when manually triggered
- **Example Generation:**

  ```elixir
  # User defines their actions (no modifications)
  actions do
    update :load_order do
      # User's business logic via Change module
      change LoadOrderLogic

      # AshJobs transformer automatically adds:
      # change AshJobs.Change
    end

    update :validate_inventory do
      # User's business logic
      change ValidateInventoryLogic

      # AshJobs transformer automatically adds:
      # change AshJobs.Change
    end
  end

  # Generated Oban triggers (one per automatic step)
  oban do
    triggers do
      trigger :process_order_load_order do
        action :load_order  # Calls user's action
        where expr(process_order_state == :load_order)
        on_error :handle_load_error
        queue :order_processing
      end

      trigger :process_order_validate_inventory do
        action :validate_inventory  # Calls user's action
        where expr(process_order_state == :validate_inventory)
        on_error :notify_inventory_error
        queue :inventory_processing
      end

      # ... one trigger per step
    end
  end
  ```

**Global Change Module (AshJobs.Change):**

The single Change module that gets added to all workflow actions:

```elixir
defmodule AshJobs.Change do
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    # 1. Detect which workflow and step this action belongs to
    workflow_info = detect_workflow(changeset.action.name, changeset.resource)

    if workflow_info do
      # 2. Determine next step based on on_success routing
      next_step = get_next_step(workflow_info, :on_success)
      state_attr = :"#{workflow_info.name}_state"

      # Transition to next state and schedule Oban trigger
      changeset
      |> Ash.Changeset.force_change_attribute(state_attr, next_step)
      |> Ash.Changeset.after_transaction(fn _changeset, {:ok, record} ->
        # Schedule next Oban trigger outside the transaction
        # Only schedule if not a terminal state
        unless next_step in [:completed, :failed, :cancelled] do
          AshOban.schedule_and_run_triggers(
            record,
            triggers: [:"#{workflow_info.name}_#{next_step}"]
          )
        end

        {:ok, record}
      end)
    else
      # Not a workflow action, skip
      changeset
    end
  end

  defp detect_workflow(action_name, resource) do
    # Use AshJobs.Info to find which workflow this action belongs to
    AshJobs.Info.workflows!(resource)
    |> Enum.find(fn workflow ->
      Enum.any?(workflow.steps, &(&1.action == action_name))
    end)
  end

  defp get_next_step(workflow_info, routing_type) do
    # Look up the on_success target from workflow definition
    # Return next step name or terminal state (:completed, :failed)
  end
end
```

**Error Handling Architecture:**

**Important:** The `AshJobs.Change` module only handles success-path routing
(`on_success`). Error routing (`on_error`) is **NOT** handled by this Change
module.

- **Why:** `Ash.Changeset.after_transaction` only runs when the action succeeds.
  Action failures never reach this code.
- **Error Routing:** Handled at the AshOban trigger level via the `on_error`
  option in generated triggers:
  ```elixir
  trigger :process_order_load_order do
    action :load_order
    where expr(process_order_state == :load_order)
    on_error :handle_load_error  # Error routing configured HERE
    queue :order_processing
  end
  ```
- **Design Rationale:** This separation of concerns is by design:

  - Change module: Success-path workflow routing
  - Oban triggers: Error detection and error-path routing
  - User actions: Business logic implementation

- 📖 [AshOban DSL Reference](https://hexdocs.pm/ash_oban/dsl-ashoban.html)
- 📖 [Ash.Resource.Change](https://hexdocs.pm/ash/Ash.Resource.Change.html)

**Database Requirements:**

- PostgreSQL recommended (for Oban's job table)
- Oban migration required: `mix ecto.gen.migration add_oban_jobs_table`
- Schema additions per workflow (generated by AshJobs):
  - `<workflow_name>_state` column (atom/string) - Current workflow step
  - `<workflow_name>_started_at` column (datetime)
  - `<workflow_name>_completed_at` column (datetime)
  - `<workflow_name>_last_error` column (text)
- User defines their own attributes for data passing between steps (no special
  context management)

**Configuration Requirements:**

- `config/config.exs`: Oban configuration
  ```elixir
  config :my_app, Oban,
    repo: MyApp.Repo,
    queues: [default: 10, workflows: 20],
    plugins: [Oban.Plugins.Pruner]
  ```
- Application supervision tree: Add Oban to supervisors

---

## 5. Test Impact & Patterns

### Testing Strategy

**Unit Testing Approach:**

- Test each transformer independently
- Mock Spark.Dsl.Transformer functions for isolation
- Verify DSL entity generation without full resource compilation

**Integration Testing Approach:**

- Define full test resources with workflows
- Execute workflows end-to-end
- Verify state transitions and persistence
- Test Oban job execution (use Oban.Testing)

**Test Helper Patterns:**

- Use `Oban.Testing.with_testing_mode/2` for synchronous job execution
- Create reusable test resource macros
- Mock external dependencies in action implementations

### Tests Requiring Creation

**Transformer Tests:**

- `test/ash_jobs/transformers/validate_workflow_test.exs`

  - Test circular dependency detection
  - Test invalid step references
  - Test missing action validation

- `test/ash_jobs/transformers/resolve_conflicts_test.exs`

  - Test detection of pre-existing actions
  - Test attribute conflict handling
  - Test warning message generation

- `test/ash_jobs/transformers/build_workflow_test.exs`
  - Test attribute generation
  - Test action generation for missing actions
  - Test state machine entity creation
  - Test Oban trigger creation

**Integration Tests:**

- `test/ash_jobs/workflow_execution_test.exs`
  - Test successful workflow completion
  - Test step failure and error transitions
  - Test retry logic and max attempts
  - Test intermediate state persistence
  - Test timeout handling

**Edge Case Tests:**

- `test/ash_jobs/edge_cases_test.exs`
  - Test workflows with single step
  - Test workflows with parallel steps (future)
  - Test workflows with conditional branching
  - Test multiple workflows in same resource

### Testing Tools & Libraries

**Required Test Dependencies:**

- `mox` ~> 1.1 - Mocking library for Elixir
  - For mocking external dependencies
  - 📖 [Mox Documentation](https://hexdocs.pm/mox/Mox.html)

**Oban Testing Support:**

- Built-in: `Oban.Testing` module
  - 📖 [Oban Testing Guide](https://hexdocs.pm/oban/testing.html)
  - Use `Oban.Testing.perform_job/3` for synchronous execution
  - Use `Oban.Testing.with_testing_mode/2` for test isolation

---

## 6. Configuration & Environment

### Configuration Files to Create/Update

**mix.exs:22-27** - Add dependencies:

```elixir
defp deps do
  [
    {:ash, "~> 3.0"},
    {:spark, "~> 2.0"},
    {:ash_state_machine, "~> 0.2.12"},
    {:ash_oban, "~> 0.4.12"},
    {:oban, "~> 2.15"},

    # Development & Testing
    {:ex_doc, "~> 0.31", only: :dev, runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:mox, "~> 1.1", only: :test}
  ]
end
```

**mix.exs:15-18** - Update application:

```elixir
def application do
  [
    extra_applications: [:logger],
    mod: {AshJobs.Application, []}  # If supervision tree needed
  ]
end
```

**.formatter.exs** - Add Spark DSL formatting:

```elixir
[
  import_deps: [:ash, :ash_state_machine, :ash_oban],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter]
]
```

**New Configuration File** - `config/config.exs`:

```elixir
import Config

# This library doesn't need runtime config, but users will need:
# config :my_app, :ash_jobs,
#   default_timeout: 300,
#   default_retry_attempts: 3,
#   default_retry_delay: 60

import_config "#{config_env()}.exs"
```

**New Configuration File** - `config/dev.exs`:

```elixir
import Config

# Development-specific settings
```

**New Configuration File** - `config/test.exs`:

```elixir
import Config

# Test-specific settings
config :ash_jobs, :test_mode, true
```

### Environment Variables

**For Library Development:**

- None required (library code only)

**For Users of AshJobs:**

- `DATABASE_URL` - PostgreSQL connection (for Oban)
- `OBAN_QUEUES` - Queue configuration (optional)

---

## 7. Required New Dependencies/Patterns

### Core Dependencies (User Approval Required)

⚠️ **User Decision Required:**

**ash_state_machine (~> 0.2.12):**

- **Purpose:** State machine functionality for workflow steps
- **Rationale:** Essential for state transitions, no viable alternative in Ash
  ecosystem
- **Recommendation:** **APPROVE** - This is a stated requirement in the project
  brief

**ash_oban (~> 0.4.12):**

- **Purpose:** Background job execution and scheduling
- **Rationale:** Essential for async step execution, no viable alternative in
  Ash ecosystem
- **Recommendation:** **APPROVE** - This is a stated requirement in the project
  brief

**oban (~> 2.15):**

- **Purpose:** Job processing engine (peer dependency of ash_oban)
- **Rationale:** Required by ash_oban, battle-tested production solution
- **Alternative:** Could use GenServer-based scheduling, but loses reliability
  features
- **Recommendation:** **APPROVE** - Standard dependency for ash_oban

### Development Dependencies

**spark (~> 2.0):**

- **Purpose:** DSL framework underlying Ash
- **Rationale:** Required for building Ash extensions
- **Recommendation:** **APPROVE** - Essential for extension development

**credo, dialyxir, ex_doc:**

- **Purpose:** Code quality, type checking, documentation
- **Rationale:** Standard Elixir development tools
- **Recommendation:** **APPROVE** - Best practices for library development

### Optional Dependencies (Future Consideration)

**telemetry (~> 1.2):**

- **Purpose:** Instrumentation and monitoring
- **Use Case:** Emit events for workflow execution, step timing, failures
- **Recommendation:** Consider for v0.2.0+ for production observability

**nimble_options (~> 1.1):**

- **Purpose:** Schema validation for DSL options
- **Use Case:** Validate workflow configuration at compile time
- **Recommendation:** Consider if DSL option validation becomes complex

---

## 8. Risk Assessment

### Breaking Changes

**Risk Level: MEDIUM**

1. **State Machine Integration Conflicts**

   - **Risk:** Users may already use ash_state_machine in their resources
   - **Impact:** Generated state machine config could conflict with existing
     config
   - **Mitigation:**
     - Detect existing state_machine DSL usage
     - Error with clear message if state_attribute conflicts
     - Document that AshJobs requires exclusive state machine control for
       workflow attribute
   - **Severity:** HIGH - Could prevent adoption

2. **Action Name Collisions**

   - **Risk:** Generated actions may collide with user-defined actions
   - **Impact:** Compilation errors or unexpected behavior override
   - **Mitigation:**
     - Use `Ash.Resource.Builder.add_new_action` (fails gracefully)
     - Emit warning when action already exists
     - Document action naming conventions
   - **Severity:** MEDIUM - Solvable through detection

3. **Attribute Type Mismatches**
   - **Risk:** Generated attributes exist with incompatible types
   - **Impact:** Type mismatches, compilation errors, data corruption
   - **Mitigation:**
     - Validate existing attribute types match expected types
     - Skip generation if correct type already exists (flexible)
     - Clear error messages for type mismatches
     - Allow custom attribute name configuration via DSL
   - **Severity:** MEDIUM - Detectable at compile time with clear errors

### Performance Implications

**Risk Level: LOW-MEDIUM**

1. **Transformer Overhead**

   - **Impact:** Increased compilation time for resources with complex workflows
   - **Mitigation:** Keep transformers efficient, avoid unnecessary AST
     traversal
   - **Severity:** LOW - Compile-time only

2. **State Persistence Overhead**

   - **Impact:** Database write on every step transition
   - **Mitigation:**
     - Make intermediate persistence optional via DSL option
     - Use efficient map/jsonb storage
     - Consider batching in future versions
   - **Severity:** MEDIUM - Runtime performance concern

3. **Oban Queue Congestion**
   - **Impact:** Workflow steps competing for Oban worker slots
   - **Mitigation:**
     - Allow per-workflow queue configuration
     - Document queue tuning recommendations
     - Consider priority levels for critical workflows
   - **Severity:** MEDIUM - Can impact user applications

### Security Touchpoints

**Risk Level: LOW**

1. **State Data Exposure**

   - **Risk:** Workflow context map may contain sensitive data
   - **Impact:** Sensitive data in database logs, backups, error messages
   - **Mitigation:**
     - Document security best practices for context data
     - Consider encryption option for context field
     - Sanitize error messages
   - **Severity:** MEDIUM - User responsibility, but library should guide

2. **Action Authorization**

   - **Risk:** Generated actions bypass user-defined authorization
   - **Impact:** Privilege escalation, unauthorized workflow execution
   - **Mitigation:**
     - Respect existing action authorization policies
     - Don't override user-defined action security
     - Document authorization considerations
   - **Severity:** HIGH - Security critical

3. **Oban Job Data Security**
   - **Risk:** Workflow context stored in Oban job args
   - **Impact:** Sensitive data in Oban jobs table
   - **Mitigation:**
     - Store only record IDs in job args, not full context
     - Load current resource state from database at execution
     - Document data security practices
   - **Severity:** MEDIUM - Standard Oban security concern

### Migration Complexity

**Risk Level: LOW**

1. **Database Migrations**

   - **Complexity:** Users need to add workflow attribute columns
   - **Impact:** Manual migration creation required
   - **Mitigation:**
     - Provide migration generator: `mix ash_jobs.gen.migration`
     - Document migration requirements clearly
     - Consider auto-migration in development mode
   - **Severity:** LOW - Standard Ash workflow

2. **Existing Resource Migration**
   - **Complexity:** Adding AshJobs to existing resources requires planning
   - **Impact:** Backfilling data, handling existing records
   - **Mitigation:**
     - Provide default values for workflow attributes
     - Document migration strategies for existing data
     - Consider "opt-in" mode for existing records
   - **Severity:** MEDIUM - User migration complexity

---

## 9. Third-Party Integrations & External Services

### Primary Dependencies

**Oban (Background Job Processing)**

- **Integration Type:** Job queue and worker management
- **Current Status:** NEW INTEGRATION - Not found in codebase
- **Context-Specific Documentation:**
  - 📖 [Oban Documentation](https://hexdocs.pm/oban/Oban.html) - Core Oban
    features
  - 📖 [Oban Installation](https://hexdocs.pm/oban/installation.html) - Setup
    guide
  - 📖 [Oban.Worker Behaviour](https://hexdocs.pm/oban/Oban.Worker.html) -
    Worker implementation
  - 📖 [Oban Testing](https://hexdocs.pm/oban/testing.html) - Test mode and
    helpers
  - 📖 [Oban Pro Features](https://getoban.pro/) - Advanced features (optional)
- **Security Considerations:**
  - Oban stores job data in PostgreSQL - ensure proper database security
  - Job args should not contain sensitive data directly
  - Use encrypted columns for sensitive workflow context
- **Version Information:**
  - Target version: 2.15+
  - AshOban peer dependency requirement
  - 📖 [Oban Changelog](https://hexdocs.pm/oban/changelog.html) - Version
    updates

**PostgreSQL (Required for Oban)**

- **Integration Type:** Database backend for Oban jobs table
- **Current Status:** Assumed available (standard Ash setup)
- **Requirements:**
  - Oban requires PostgreSQL for its jobs table
  - JSONB support needed for workflow context storage
  - Advisory locks used for job claiming
- **Migration Required:**
  ```bash
  mix ecto.gen.migration add_oban_jobs_table
  # Then run: Oban.Migration.up(version: 12)
  ```
- 📖 [Oban Migrations](https://hexdocs.pm/oban/Oban.Migration.html)

### Ash Ecosystem Integrations

**AshStateMachine**

- **Integration Type:** Compile-time DSL extension
- **Purpose:** State transition management for workflow steps
- **Documentation:**
  - 📖
    [Getting Started](https://hexdocs.pm/ash_state_machine/getting-started-with-ash-state-machine.html)
  - 📖
    [DSL Reference](https://hexdocs.pm/ash_state_machine/dsl-ashstatemachine.html)
  - 📖 [State Charts](https://hexdocs.pm/ash_state_machine/state-charts.html)
  - 📖 [GitHub Repository](https://github.com/ash-project/ash_state_machine)
- **Integration Pattern:**
  - AshJobs transformers generate state_machine DSL entities
  - Each workflow step becomes a state transition
  - Success/failure paths define allowed transitions

**AshOban**

- **Integration Type:** Compile-time DSL extension + runtime execution
- **Purpose:** Background job scheduling and execution
- **Documentation:**
  - 📖
    [Getting Started](https://hexdocs.pm/ash_oban/getting-started-with-ash-oban.html)
  - 📖 [Triggers DSL](https://hexdocs.pm/ash_oban/triggers.html)
  - 📖 [Scheduled Actions](https://hexdocs.pm/ash_oban/scheduled-actions.html)
  - 📖 [GitHub Repository](https://github.com/ash-project/ash_oban)
- **Integration Pattern:**
  - AshJobs transformers generate oban trigger DSL entities
  - Each workflow step gets a trigger with execution conditions
  - Retry logic configured per-step via trigger options

**Reactor (Pattern Reference)**

- **Integration Type:** Architectural patterns (not direct dependency)
- **Purpose:** Workflow orchestration patterns and saga concepts
- **Documentation:**
  - 📖 [Reactor Core](https://hexdocs.pm/reactor/readme.html)
  - 📖 [Ash.Reactor Integration](https://hexdocs.pm/ash/reactor.html)
  - 📖
    [Advanced Reactor Patterns](https://github.com/ash-project/ash/blob/main/documentation/topics/advanced/reactor.md)
- **Integration Pattern:**
  - DSL design inspiration (step-based workflow definition)
  - Saga patterns for compensation/rollback (future feature)
  - NOT a runtime dependency - AshJobs implements own execution

### No External API Integrations Detected

This library is pure Elixir/Ash infrastructure with no third-party service
integrations required. Users may integrate external services within their action
implementations, but that's outside the library's scope.

---

## 10. Unclear Areas Requiring Clarification

### DSL Design Decisions

1. **Parallel Step Execution**

   - **Question:** Should the library support parallel step execution?
   - **Current Design:** Sequential execution only - one step at a time
   - **Rationale:** Simplifies implementation and avoids database mutation race
     conditions
   - **Options:**
     - Sequential only (v0.1.0 approach)
     - Parallel with in-memory coordination (Task.async within single job)
     - Parallel with separate jobs per step (complex, requires optimistic
       locking)
   - **Recommendation:** Sequential for v0.1.0, evaluate parallel in v0.2.0
     based on real-world needs
   - **User Input Needed:** Confirm sequential-only acceptable for initial
     release

2. **Conditional Branching**

   - **Question:** How should conditional step selection work beyond error
     handling?
   - **Current Design:** Binary branching via `on_success`/`on_error`
   - **Options:**
     - Binary only (success/error)
     - Multi-way branching based on return values
     - Expression-based routing (`:step if expr(...)`)
     - Switch-case style routing
   - **Recommendation:** Start with binary, document multi-way as future feature
   - **User Input Needed:** Confirm binary branching sufficient for v0.1.0

3. **Nested Workflows**
   - **Question:** Should one workflow be able to invoke another?
   - **Use Case:** Complex multi-stage processes (e.g., "fulfillment" workflow
     calls "payment" workflow)
   - **Options:**
     - Not supported initially
     - Support via special `workflow_step` type
   - **Recommendation:** Defer to v0.2.0+
   - **User Input Needed:** Confirm deferral acceptable

### State Management Details

4. **Context Data Structure**

   - **Question:** What's the schema for workflow context storage?
   - **Options:**
     - Free-form map (flexible, no validation)
     - Typed embedded schema (validated, documented)
     - User-defined schema via DSL option
   - **Recommendation:** Free-form map for v0.1.0, add typed option in v0.2.0
   - **User Input Needed:** Confirm flexible map acceptable initially

5. **State Persistence Timing**

   - **Question:** When exactly should state be persisted?
   - **Options:**
     - Before each step execution (safer, more DB writes)
     - After each step success (fewer writes, lose state on crash)
     - Configurable per-step via DSL
   - **Recommendation:** Before execution by default, make configurable
   - **User Input Needed:** Confirm default timing

6. **Historical State Tracking**
   - **Question:** Should the library track step execution history?
   - **Use Case:** Debugging, auditing, analytics
   - **Options:**
     - No history (minimal storage)
     - Append-only log in context map
     - Separate history table/resource
   - **Recommendation:** No built-in history in v0.1.0, document user patterns
   - **User Input Needed:** Confirm history tracking out of scope

### Error Handling & Recovery

7. **Retry Strategy Configuration**

   - **Question:** How granular should retry configuration be?
   - **Current Design:** Per-step retry_attempts and retry_delay_seconds
   - **Options:**
     - Fixed delay only
     - Exponential backoff
     - Custom retry strategy callbacks
   - **Recommendation:** Fixed delay for v0.1.0, add backoff in v0.2.0
   - **User Input Needed:** Confirm fixed delay sufficient

8. **Compensation/Rollback**

   - **Question:** Should workflows support automatic rollback on failure?
   - **Use Case:** Saga pattern - undo previous steps if later step fails
   - **Options:**
     - No automatic rollback (user handles in actions)
     - `on_compensate` DSL option per step
     - Full saga support like Reactor
   - **Recommendation:** No automatic rollback in v0.1.0, defer to v0.2.0
   - **User Input Needed:** Confirm compensation out of scope for now

9. **Timeout Behavior**
   - **Question:** What happens when a step times out?
   - **Options:**
     - Fail workflow immediately
     - Retry automatically
     - Transition to timeout-specific state
   - **Recommendation:** Fail workflow, user can configure retry to handle
   - **User Input Needed:** Confirm timeout=failure approach

### Conflict Resolution Strategy

10. **Action Conflict Handling**

    - **Question:** What should happen when user has declared an action that
      AshJobs would generate?
    - **Options:**
      - Error (strict, prevents conflicts)
      - Warn and skip generation (flexible, uses user's action)
      - Error if signature doesn't match expected (validation)
    - **Recommendation:** Warn and skip - trust user's implementation
    - **User Input Needed:** Confirm this approach

11. **Attribute Conflict Handling**
    - **Question:** What if workflow attribute names collide with existing
      attributes?
    - **Decision:** Flexible type-based validation (IMPLEMENTED)
    - **Approach:**
      - Allow users to pre-define workflow attributes
      - Validate existing attributes have correct type
      - Skip generation if correct type exists
      - Error only on type mismatch with clear message
      - Allow custom attribute names via DSL
    - **Rationale:** Maximizes flexibility while maintaining type safety

### Integration Specifics

12. **State Machine Attribute Sharing**

    - **Question:** Can AshJobs and AshStateMachine share the same state
      attribute?
    - **Use Case:** Resource has multiple state machines
    - **Options:**
      - Each workflow requires dedicated state attribute (safe, simple)
      - Allow sharing if user explicitly configures (complex, error-prone)
    - **Recommendation:** Dedicated attribute per workflow (default:
      `<workflow_name>_state`)
    - **User Input Needed:** Confirm dedicated attributes approach

13. **Oban Queue Assignment**
    - **Question:** How should workflows map to Oban queues?
    - **Options:**
      - All workflows use default queue
      - Per-workflow queue configuration via DSL
      - Per-step queue configuration
    - **Recommendation:** Per-workflow queue with default to `:workflows` queue
    - **User Input Needed:** Confirm this granularity

---

## 11. Architecture Deep Dive

### Module Structure

```
lib/ash_jobs/
├── ash_jobs.ex                           # Main extension module
├── dsl/
│   ├── sections.ex                       # DSL section definitions
│   ├── entities/
│   │   ├── workflow.ex                   # Workflow entity schema
│   │   └── step.ex                       # Step entity schema
│   └── schema.ex                         # Shared schema definitions
├── transformers/
│   ├── validate_workflow.ex              # Validation transformer
│   ├── resolve_conflicts.ex              # Conflict detection
│   ├── build_workflow.ex                 # Main code generation
│   ├── integrate_state_machine.ex        # State machine setup
│   └── integrate_oban.ex                 # Oban trigger setup
├── change.ex                             # Global Change module (routing logic)
├── verifiers/
│   └── workflow_consistency.ex           # Post-compilation verification
├── info.ex                               # Introspection module (generated)
├── helpers.ex                            # Utility functions
└── behaviours/
    └── workflow_handler.ex               # Extension point behaviour (optional)
```

### DSL Design (Proposed)

```elixir
workflows do
  workflow :order_processing do
    state_attribute :order_state          # Optional, default: :order_processing_state
    oban_queue :order_workflows           # Optional, default: :workflows

    # Steps execute sequentially via explicit routing
    # Initial step (no on_success means it's the entry point)
    step :validate_order do
      action :validate_order              # Required: user's action name

      # Explicit routing
      on_success :process_payment
      on_error :notify_validation_error

      timeout_seconds 30                  # Optional: step timeout
      queue :validation                   # Optional: queue name
    end

    step :process_payment do
      action :charge_card                 # Calls payment service internally

      on_success :ship_order
      on_error :refund_order

      retry_attempts 3                    # Optional: retry count
      retry_delay_seconds 60              # Optional: delay between retries
      queue :payments
    end

    # Manual pause point - waits for external completion
    step :await_user_confirmation do
      action :send_confirmation_request
      trigger false                       # No Oban trigger - must be advanced manually
      state :awaiting_confirmation        # Optional: override generated state name (defaults to :await_user_confirmation)

      on_success :ship_order
      on_error :handle_confirmation_timeout
    end

    step :ship_order do
      action :create_shipment             # Calls shipment service internally

      on_success :mark_complete
      on_error :handle_shipping_error
    end

    step :mark_complete do
      action :mark_complete

      # Terminal step - workflow completes
      on_success :completed
    end

    # Error handling steps
    step :notify_validation_error do
      action :send_validation_email

      on_complete :failed  # Terminal state
    end

    step :refund_order do
      action :process_refund

      on_complete :failed
    end

    step :handle_shipping_error do
      action :notify_shipping_issue

      on_complete :failed
    end
  end
end

# User defines regular attributes for data passing
attributes do
  attribute :customer_id, :uuid
  attribute :calculated_total, :decimal
  attribute :payment_receipt_id, :string
  attribute :shipment_id, :uuid
end
```

### Transformer Pipeline Order

```
1. ValidateWorkflow
   - Validate all step on_success/on_error references point to existing steps or terminal states
   - Detect circular routing loops (e.g., step A -> step B -> step A)
   - Ensure at least one step has no incoming on_success (entry point)
   - Ensure all non-terminal steps have on_success defined
   - Validate terminal states (:completed, :failed, :cancelled) are only in on_success/on_complete
   - Verify user-defined actions exist for each step

2. ResolveConflicts
   - Scan for existing attributes matching generated names (e.g., <workflow>_state)
   - Validate type compatibility for existing attributes (fail only on type mismatch)
   - Mark existing attributes to skip generation if types are correct
   - Verify user has defined all required actions for their steps
   - Build attribute generation map for BuildWorkflow

3. BuildWorkflow
   - Generate workflow state attributes (state, started_at, completed_at, last_error)
   - Add global AshJobs.Change to all workflow actions (via after_action hook)
   - NO modifications to user's action logic - Change runs after their changes
   - NO executor actions generated - users define their own actions

4. IntegrateStateMachine
   - Add state_machine DSL section
   - Configure state attribute
   - Generate one state per step (uses custom `state` option if provided, otherwise defaults to step name)
   - Generate transitions based on on_success/on_error routing
   - Add terminal states: :completed, :failed, :cancelled

5. IntegrateOban
   - Add oban DSL section if not present
   - Generate one trigger per automatic step (skip steps with `trigger false`)
   - Each trigger filters on its step state (uses custom `state` if provided)
   - Configure queue, retry, and error handling per step
   - Triggers call user's actions directly

6. WorkflowConsistency (Verifier - runs after all transformers)
   - Verify state machine transitions match on_success/on_error routing
   - Verify Oban triggers reference valid step actions
   - Verify all steps are reachable from entry point
   - Verify no dead-end steps (except terminal states)
```

### Code Generation Strategy

**Attributes Generated (per workflow):**

- `<workflow>_state` (atom) - Current step in workflow: `:load_order`,
  `:validate_inventory`, etc.
  - Also includes terminal states: `:completed`, `:failed`, `:cancelled`
- `<workflow>_started_at` (datetime) - Workflow start time
- `<workflow>_completed_at` (datetime) - Workflow completion time
- `<workflow>_last_error` (text) - Last error message if any

**NO executor actions generated** - Users define their own actions with business
logic

**Global Change Module Added:**

- `AshJobs.Change` module automatically added to all workflow actions via
  transformer
- Change runs after user's changes complete successfully
- Handles state transitions and Oban trigger scheduling
- NO modifications to user's action logic

**State Machine Entities Generated:**

- One state per workflow step (e.g., `:load_order`, `:validate_inventory`)
- Uses custom `state` option value if provided, otherwise defaults to step name
- Terminal states: `:completed`, `:failed`, `:cancelled`
- Transitions generated from `on_success`/`on_error` routing
- Example:

  ```elixir
  state_machine do
    initial_states [:load_order]
    state_attribute :process_order_state

    transitions do
      transition :to_validate_inventory, from: :load_order, to: :validate_inventory
      transition :to_calculate_total, from: :validate_inventory, to: :calculate_total
      transition :to_completed, from: :mark_complete, to: :completed
      transition :to_failed, from: :handle_error, to: :failed
    end
  end
  ```

**Oban Entities Generated:**

- One trigger per automatic step (manual pause steps don't get triggers)
- Each trigger calls user's action directly
- Trigger filters on specific step state
- Queue configuration from step DSL
- Example:
  ```elixir
  oban do
    triggers do
      trigger :process_order_load_order do
        action :load_order  # User's action
        where expr(process_order_state == :load_order)
        on_error :handle_load_error
        queue :order_processing
      end
    end
  end
  ```

### Global Change Module Logic

**Simplified Architecture:**

No executor actions are generated. Instead, users define their own actions with
business logic, and AshJobs.Change module is automatically added to:

1. Trigger the state transition based on `on_success`
2. Call `run_oban_trigger` to schedule the next step

That's it! No complex orchestration, input resolution, or dependency management.

**Global Change Module (AshJobs.Change):**

```elixir
defmodule AshJobs.Change do
  @moduledoc """
  Global Change module that handles workflow routing.
  Automatically added to all workflow actions by BuildWorkflow transformer.

  Simple logic:
  1. Transition to on_success state
  2. Trigger next Oban job
  """
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    # Detect which step this action belongs to
    step_info = get_step_for_action(changeset.resource, changeset.action.name)

    if step_info do
      state_attr = :"#{step_info.workflow_name}_state"
      next_state = step_info.on_success

      # Transition to next state and schedule Oban trigger
      changeset
      |> Ash.Changeset.force_change_attribute(state_attr, next_state)
      |> Ash.Changeset.after_transaction(fn _changeset, {:ok, record} ->
        # Schedule next Oban trigger outside the transaction
        # Only schedule if not a terminal state
        unless next_state in [:completed, :failed, :cancelled] do
          trigger_name = :"#{step_info.workflow_name}_#{next_state}"
          AshOban.run_trigger(record, trigger_name)
        end

        {:ok, record}
      end)
    else
      # Not a workflow action, skip
      changeset
    end
  end

  defp get_step_for_action(resource, action_name) do
    # Look up step info from AshJobs.Info
    # Returns: %{workflow_name: :foo, on_success: :bar}
  end
end
```

**Example Flow:**

1. User's order resource has `:load_order` action with their business logic
2. Oban trigger fires when state is `:load_order`
3. Trigger calls user's `:load_order` action
4. User's Change modules run (business logic)
5. `AshJobs.Change` runs last: transitions to `:validate_inventory` + triggers
   Oban job
6. Process repeats until terminal state reached

**That's the whole routing logic** - just state transitions and Oban triggers!

### Conflict Resolution Logic

**Flexible Strategy:**

Since users define all actions themselves and we only generate attributes,
conflict resolution focuses on:

1. Attribute type validation (not naming conflicts)
   - Allow users to pre-define workflow attributes if desired
   - Only fail if existing attribute has wrong type
   - Skip generation if correct type already exists
2. Verifying user actions exist
3. No executor action conflicts (we don't generate executors anymore)

```elixir
defmodule AshJobs.Transformers.ResolveConflicts do
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def transform(dsl_state) do
    # Get workflows from DSL state using Transformer.get_entities
    workflows = Transformer.get_entities(dsl_state, [:workflows])
    existing_actions = Ash.Resource.Info.actions(dsl_state.resource)
    existing_attributes = Ash.Resource.Info.attributes(dsl_state.resource)

    # Check for attribute conflicts (workflow state attributes)
    for workflow <- workflows do
      state_attr = workflow.state_attribute || :"#{workflow.name}_state"

      # Check if state attribute exists and validate its type
      if existing_attr = Enum.find(existing_attributes, &(&1.name == state_attr)) do
        # Attribute exists - validate type is compatible (atom)
        unless existing_attr.type == :atom do
          raise Spark.Error.DslError,
            module: dsl_state.resource,
            message: """
            Workflow state attribute '#{state_attr}' exists but has wrong type.
            Expected: :atom
            Found: #{inspect(existing_attr.type)}

            The state attribute must be an atom to work with ash_state_machine.
            """
        end
        # Type is correct - skip generation, use existing attribute
      end

      # Check other generated attributes for type compatibility
      for {attr_suffix, expected_type} <- [
        {"_started_at", :utc_datetime_usec},
        {"_completed_at", :utc_datetime_usec},
        {"_last_error", :string}
      ] do
        attr_name = :"#{workflow.name}#{attr_suffix}"

        if existing_attr = Enum.find(existing_attributes, &(&1.name == attr_name)) do
          # Attribute exists - validate type is compatible
          unless existing_attr.type == expected_type do
            raise Spark.Error.DslError,
              module: dsl_state.resource,
              message: """
              Workflow attribute '#{attr_name}' exists but has wrong type.
              Expected: #{inspect(expected_type)}
              Found: #{inspect(existing_attr.type)}
              """
          end
          # Type is correct - skip generation, use existing attribute
        end
      end
    end

    # Validate that step actions exist (user MUST define them)
    # All steps must call actions on the current resource
    for workflow <- workflows, step <- workflow.steps do
      unless Enum.any?(existing_actions, &(&1.name == step.action)) do
        raise Spark.Error.DslError,
          module: dsl_state.resource,
          message: """
          AshJobs: Required action not found
          Workflow: #{workflow.name}
          Step: #{step.name}
          Action: #{step.action}

          All workflow steps must call actions on the current resource.
          Please define the action in your resource:

          actions do
            update :#{step.action} do
              # Your business logic here
            end
          end
          """
      end
    end

    {:ok, dsl_state}
  end
end
```

---

## 12. Implementation Phases (Recommended)

### Phase 1: Core DSL & Transformers (v0.1.0-alpha)

- [ ] Define DSL structure (workflows, steps)
- [ ] Implement ValidateWorkflow transformer
- [ ] Implement ResolveConflicts transformer
- [ ] Implement basic BuildWorkflow transformer
- [ ] Basic attribute generation
- [ ] Unit tests for transformers

### Phase 2: State Machine Integration (v0.1.0-beta)

- [ ] Implement IntegrateStateMachine transformer
- [ ] Generate state transitions from workflow
- [ ] Test state transition flows
- [ ] Handle terminal states correctly

### Phase 3: Oban Integration (v0.1.0-rc)

- [ ] Implement IntegrateOban transformer
- [ ] Generate triggers for step execution
- [ ] Implement retry logic
- [ ] Test background job execution
- [ ] Handle failures and timeouts

### Phase 4: Global Change Module & State Persistence (v0.1.0)

- [ ] Implement AshJobs.Change module (global routing logic)
- [ ] Add Change to workflow actions via transformer
- [ ] Implement state transition logic (on_success/on_error handling)
- [ ] Implement Oban trigger scheduling
- [ ] Handle terminal states (completed, failed, cancelled)
- [ ] Test end-to-end workflow execution
- [ ] Test state persistence between steps
- [ ] Integration tests for full workflows
- [ ] Test manual step advancement (trigger: false)
- [ ] Test error handling and on_error routing

### Phase 5: Polish & Documentation (v0.1.0 release)

- [ ] Complete API documentation
- [ ] Write usage guides with sequential workflow examples
- [ ] Create example projects showing on_success/on_error routing patterns
- [ ] Document manual pause points and external completion
- [ ] Performance testing (especially database state updates)
- [ ] Security review

### Future Phases (Post v0.1.0)

- v0.2.0: Multi-way conditional branching (beyond error handling)
- v0.2.0: Typed context schemas
- v0.2.0: Advanced retry strategies (exponential backoff)
- v0.3.0: Compensation/saga patterns
- v0.3.0: Nested workflow support
- v0.3.0: Dynamic step generation
- v0.4.0: Telemetry integration
- v0.4.0: Workflow analytics and monitoring
- v0.4.0: Workflow visualization tools

---

## 13. Documentation Links Summary

### Core Ash Framework

- 📖 [Writing Extensions Guide](https://hexdocs.pm/ash/writing-extensions.html)
- 📖 [Spark.Dsl.Extension](https://hexdocs.pm/spark/Spark.Dsl.Extension.html)
- 📖
  [Spark.Dsl.Transformer](https://hexdocs.pm/spark/Spark.Dsl.Transformer.html)
- 📖 [Spark.InfoGenerator](https://hexdocs.pm/spark/Spark.InfoGenerator.html)
- 📖 [Ash.Resource.Builder](https://hexdocs.pm/ash/Ash.Resource.Builder.html)
- 📖 [Ash.Resource.Change](https://hexdocs.pm/ash/Ash.Resource.Change.html)

### State Machine

- 📖
  [AshStateMachine Getting Started](https://hexdocs.pm/ash_state_machine/getting-started-with-ash-state-machine.html)
- 📖
  [AshStateMachine DSL](https://hexdocs.pm/ash_state_machine/dsl-ashstatemachine.html)
- 📖
  [AshStateMachine State Charts](https://hexdocs.pm/ash_state_machine/state-charts.html)
- 📖 [AshStateMachine GitHub](https://github.com/ash-project/ash_state_machine)

### Background Jobs

- 📖
  [AshOban Getting Started](https://hexdocs.pm/ash_oban/getting-started-with-ash-oban.html)
- 📖 [AshOban DSL Reference](https://hexdocs.pm/ash_oban/dsl-ashoban.html)
- 📖
  [AshOban Scheduled Actions](https://hexdocs.pm/ash_oban/scheduled-actions.html)
- 📖 [AshOban GitHub](https://github.com/ash-project/ash_oban)
- 📖 [Oban Documentation](https://hexdocs.pm/oban/Oban.html)
- 📖 [Oban Installation](https://hexdocs.pm/oban/installation.html)
- 📖 [Oban Testing](https://hexdocs.pm/oban/testing.html)
- 📖 [Oban.Worker](https://hexdocs.pm/oban/Oban.Worker.html)

### Workflow Patterns

- 📖 [Reactor Documentation](https://hexdocs.pm/reactor/readme.html)
- 📖 [Ash.Reactor](https://hexdocs.pm/ash/reactor.html)
- 📖
  [Advanced Reactor Patterns](https://github.com/ash-project/ash/blob/main/documentation/topics/advanced/reactor.md)

### Testing

- 📖 [Mox Documentation](https://hexdocs.pm/mox/Mox.html)
- 📖 [ExUnit Documentation](https://hexdocs.pm/ex_unit/ExUnit.html)

---

## 14. Success Criteria

This research phase is complete when:

- ✅ All current project dependencies analyzed (greenfield confirmed)
- ✅ Required new dependencies identified with versions
- ✅ Complete file structure planned with line-by-line generation strategy
- ✅ Integration patterns for ash_state_machine and ash_oban documented
- ✅ Conflict resolution strategy defined and documented
- ✅ State persistence architecture designed
- ✅ All risks identified and mitigation strategies proposed
- ✅ All unclear areas flagged for user clarification
- ✅ Multi-agent consultation completed (elixir-expert, research-agent,
  architecture-agent)
- ✅ Authoritative documentation links gathered for all dependencies
- ✅ Testing strategy and requirements documented
- ✅ Implementation phases proposed

**Ready for next phase:** ✅ **PLAN** - Strategic implementation planning

---

## Next Steps

1. **User Review:** Review this research document and provide answers to
   "Unclear Areas Requiring Clarification"
2. **Dependency Approval:** Confirm all required dependencies are acceptable
3. **Phase Planning:** Proceed to `/plan` command to create detailed
   implementation strategy
4. **Architecture Validation:** Confirm proposed DSL structure and transformer
   pipeline

---

**Research Orchestrator:** Primary coordinator **Agent Consultations:**

- elixir-expert: Ash extension patterns and best practices ✅
- research-agent: Ash ecosystem library documentation ✅
- architecture-agent: Module structure and integration architecture ✅

**Confidence Level:** HIGH - All information from official sources and expert
consultation
