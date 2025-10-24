# AshJobs Library - Strategic Implementation Plan

**Topic:** Building ash_jobs library with state machine DSL and Oban integration
**Date:** 2025-10-14 **Phase:** Strategic Implementation Planning **Status:**
PARTIALLY UPDATED - See summary.md for latest architecture decisions

**⚠️ PARTIALLY OUTDATED DOCUMENT:** This implementation plan contains historical
architectural proposals that were later simplified. For the **current simplified
architecture**, see:

- `/notes/ash_jobs_library/summary.md` - **CURRENT ARCHITECTURE** (use this!)

## Key Outdated Sections in This Document

The following sections contain designs that were **removed** based on user
feedback:

1. **Section 3.2 - Adapter Pattern (lines 471-610)** - ❌ REMOVED - Direct
   integration instead
2. **Section 3.4 - Telemetry Module (lines 716-754)** - ❌ REMOVED - Use
   Ash/Oban telemetry
3. **Operational Helpers (Section 2.2)** - ⚠️ SIMPLIFIED - Reduced scope
4. **Module count** - ⚠️ INCORRECT - Claims 16+ files, actual is ~7 core files

**Always refer to summary.md for current design decisions.**

---

## Executive Summary

This plan transforms the comprehensive research findings into a strategic
implementation approach for the `ash_jobs` library. The library will provide a
Spark DSL extension for Ash resources that dramatically reduces boilerplate for
sequential workflow orchestration by integrating ash_state_machine and ash_oban.

**Core Value Proposition:** Transform 200+ lines of boilerplate workflow code
into 30 lines of declarative DSL while maintaining full flexibility and control.

**Strategic Approach:**

- **Foundation First:** Build solid DSL and transformer pipeline with
  comprehensive validation
- **Production Ready:** Include operational tooling from v0.1.0 (not deferred to
  future versions)
- **Extensible Architecture:** Design adapter abstractions for future
  flexibility
- **Clear Scale Targets:** Support 1,000 workflows/minute with documented tuning
  for higher scales

---

## 1. Impact Analysis Summary

### Codebase Changes from Research

**Current State:**

- Greenfield project with minimal boilerplate code
- No dependencies installed
- Single stub module: `lib/ash_jobs.ex:1-18`

**Files to Create/Modify:**

**Core Extension (4 new files):**

```
lib/ash_jobs.ex                           # Replace stub with Spark extension
lib/ash_jobs/dsl/sections.ex              # Workflow DSL section (singular)
lib/ash_jobs/dsl/entities/step.ex         # Step entity schema
lib/ash_jobs/change.ex                    # Global routing Change module
lib/ash_jobs/info.ex                      # Introspection (Spark.InfoGenerator)
lib/ash_jobs/helpers.ex                   # Operational helper functions
```

**Transformers (3 new files):**

```
lib/ash_jobs/transformers/
├── build_workflow.ex           # Change module injection
├── integrate_state_machine.ex  # State machine DSL generation
└── integrate_oban.ex           # Oban trigger generation
```

**Verifiers & Mix Tasks (2 new files):**

```
lib/ash_jobs/verifiers/
└── validate_workflow.ex        # All validation after transformers complete

lib/mix/tasks/
└── ash_jobs.install.ex         # Migration generator (CRITICAL for adoption)
```

**Configuration (4 new files):**

```
config/config.exs               # Library defaults
config/dev.exs                  # Development settings
config/test.exs                 # Test mode configuration
.formatter.exs                  # Update with Spark.Formatter
```

**Dependencies to Add (mix.exs:22-27):**

```elixir
# Core dependencies
{:ash, "~> 3.0.0"},              # Pin exact minor for stability
{:spark, "~> 2.0.0"},
{:ash_state_machine, "~> 0.2.12"},
{:ash_oban, "~> 0.4.12"},
{:oban, "~> 2.15"},

# Development dependencies
{:ex_doc, "~> 0.31", only: :dev, runtime: false},
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
{:mimic, "~> 1.11", only: :test}
```

### Existing Patterns to Follow

**Steward Project Pattern Analysis (from steward_analysis.md):**

The research identified specific pain points in the existing Steward
implementation:

- **Boilerplate heavy:** Each workflow step requires 6 separate entities
- **State management complexity:** Two-level state (generic + specific)
- **Implicit dependencies:** Step ordering via `run_oban_trigger` calls
- **Repetitive patterns:** Every step follows identical structure

**Our Solution - Pattern Improvements:**

```elixir
# OLD PATTERN (Steward) - ~35 lines per step
update :analyze_messages do
  accept []
  require_atomic? false
  change AnalyzeMessages
  change run_oban_trigger(:send_confirmation)
end

update :handle_analysis_error do
  argument :error, :map, allow_nil?: false
  accept []
  require_atomic? false
  change HandleAnalysisError
end

trigger :analyze_messages do
  action :analyze_messages
  where expr(state == :pending and type == :message_move and substate == :pending)
  on_error :handle_analysis_error
  queue :message_processing
end

# NEW PATTERN (AshJobs) - ~8 lines per step
step :analyze_messages do
  action :analyze_messages        # User's existing action
  on_success :send_confirmation
  on_error :handle_analysis_error
  queue :message_processing
end
```

**Reduction:** ~75% less boilerplate while maintaining same functionality.

---

## 2. Feature Specification

### 2.1 User Experience - DSL Design

**Primary Use Case: Sequential Multi-Step Workflows**

Users will write workflows like this:

```elixir
defmodule MyApp.Orders.FulfillmentJob do
  use Ash.Resource,
    extensions: [AshJobs, AshStateMachine, AshOban]

  workflow do
    # Optional: override default state attribute
    state_attribute :state  # Defaults to :state

    # Entry point - first step to execute
    step :load_order do
      action :load_full_order       # User's action with business logic

      on_success :validate_inventory # Next step on success
      on_error :notify_load_error    # Error handler step

      queue :order_processing
      timeout_seconds 30
    end

    step :validate_inventory do
      action :check_inventory_levels

      on_success :calculate_total
      on_error :notify_inventory_error

      queue :inventory_processing
      retry_attempts 3
      retry_delay_seconds 60
    end

    step :calculate_total do
      action :calculate_order_total

      on_success :charge_payment
      on_error :notify_calculation_error
    end

    # Manual pause point - waits for external action
    step :await_user_confirmation do
      action :send_confirmation_request
      trigger false  # No automatic Oban trigger

      on_success :charge_payment
      on_error :handle_confirmation_timeout
    end

    step :charge_payment do
      action :create_charge

      on_success :create_shipment
      on_error :refund_and_notify

      queue :payment_processing
      retry_attempts 3
    end

    step :create_shipment do
      action :create_shipment

      on_success :mark_complete
      on_error :refund_and_notify

      queue :shipping_processing
    end

    step :mark_complete do
      action :finalize_order

      on_success :completed  # Terminal state
    end

    # Error handlers
    step :refund_and_notify do
      action :process_refund
      on_complete :failed  # Terminal state
    end

    step :notify_load_error do
      action :send_load_error_email
      on_complete :failed
    end
  end

  # User defines their own attributes for data passing
  attributes do
    attribute :order_id, :uuid
    attribute :customer_id, :uuid
    attribute :order_items, {:array, :map}
    attribute :calculated_total, :decimal
    attribute :payment_receipt_id, :string
    attribute :shipment_id, :uuid

    # Note: State attribute generated by ash_state_machine (not AshJobs)
  end

  relationships do
    belongs_to :order, MyApp.Orders.Order
  end

  # User defines ALL actions - AshJobs only adds routing
  actions do
    create :create do
      accept [:order_id, :customer_id]
    end

    update :load_full_order do
      # User's business logic
      change LoadOrderItems
      # AshJobs.Change automatically added by transformer
    end

    update :check_inventory_levels do
      change ValidateInventory
      # AshJobs.Change automatically added
    end

    update :create_charge do
      change ChargePaymentProcessor
      # AshJobs.Change automatically added
    end

    # ... all other workflow actions defined by user
  end
end
```

**Generated Code (automatic via transformers):**

1. **State Machine DSL generated:**

   ```elixir
   state_machine do
     initial_states [:load_order]
     default_initial_state :load_order
     state_attribute :state

     transitions do
       transition :to_validate_inventory, from: :load_order, to: :validate_inventory
       transition :to_calculate_total, from: :validate_inventory, to: :calculate_total
       # ... all transitions from on_success/on_error routing
       transition :to_completed, from: :mark_complete, to: :completed
       transition :to_failed, from: :refund_and_notify, to: :failed
     end
   end
   ```

2. **Oban Triggers generated:**

   ```elixir
   oban do
     triggers do
       trigger :load_order do
         action :load_full_order
         where expr(state == :load_order)
         on_error :notify_load_error
         queue :order_processing
       end

       trigger :validate_inventory do
         action :check_inventory_levels
         where expr(state == :validate_inventory)
         on_error :notify_inventory_error
         queue :inventory_processing
       end

       # ... one trigger per automatic step (trigger: false steps skipped)
     end
   end
   ```

3. **Global Change Module added to all workflow actions:**
   ```elixir
   # Transformer modifies user's actions:
   update :load_full_order do
     change LoadOrderItems           # User's logic
     change AshJobs.Change           # Added automatically
   end
   ```

**Note:** The state attribute itself is generated by ash_state_machine, not
AshJobs. We just configure which attribute to use via the state_machine DSL.

### 2.2 Operational Helpers (NEW - Critical for Production)

Based on senior engineering review, these are REQUIRED for v0.1.0:

```elixir
# Get workflow status
AshJobs.get_workflow_status(FulfillmentJob, job_id)
# Returns:
# {:active, %{current_step: :validate_inventory, started_at: ~U[...], duration: 120}}
# {:stuck, %{current_step: :charge_payment, stuck_duration: 14400, reason: "Step pending for 4 hours"}}
# {:completed, %{completed_at: ~U[...], total_duration: 450}}
# {:failed, %{failed_step: :charge_payment, error: "Payment processor timeout"}}

# Retry failed workflow
AshJobs.retry_workflow(FulfillmentJob, job_id, from_step: :charge_payment)
# Resets state and triggers Oban job

# Cancel running workflow
AshJobs.cancel_workflow(FulfillmentJob, job_id, reason: "Customer cancelled order")
# Transitions to :cancelled state with audit trail

# Manual step advancement (for trigger: false steps)
AshJobs.advance_workflow(FulfillmentJob, job_id, :await_user_confirmation)
# Executes the action, Change module handles routing

# Query workflows by state
AshJobs.list_workflows_in_state(FulfillmentJob, :charge_payment)
# Returns list of jobs currently at this step

# Detect stuck workflows
AshJobs.detect_stuck_workflows(FulfillmentJob, timeout_seconds: 3600)
# Returns workflows stuck longer than timeout
```

### 2.3 Installation Experience (NEW - Migration Generator)

**Critical for Adoption:** Users need zero-friction setup.

```bash
# User runs single command
mix ash_jobs.install --resource MyApp.Orders.FulfillmentJob

# Generates:
# 1. Oban migration (if not exists)
#    priv/repo/migrations/20250114_add_oban_jobs_table.exs

# 2. Workflow attributes migration
#    priv/repo/migrations/20250114_add_workflow_attrs_to_fulfillment_jobs.exs
#    Adds: state column (timing/errors tracked in Oban's jobs table)

# 3. Config template
#    Prints instructions for config/config.exs:
#    """
#    Add to your config:
#
#    config :my_app, Oban,
#      repo: MyApp.Repo,
#      queues: [
#        default: 10,
#        order_processing: 20,
#        payment_processing: 10,
#        shipping_processing: 10
#      ]
#    """

# 4. Supervision tree instructions
#    Prints:
#    """
#    Add Oban to your application supervision tree:
#
#    children = [
#      MyApp.Repo,
#      {Oban, Application.fetch_env!(:my_app, Oban)},
#      # ...
#    ]
#    """
```

---

## 3. Technical Design

### 3.1 Architecture Overview

**Pattern: Spark DSL Extension with Transformer Pipeline**

```
User defines DSL ──────────> Compile Time ──────────> Runtime
     │                            │                       │
     │                            │                       │
  workflow {}              Transformers              Generated:
  step {}                  (modify DSL)              - State Machine DSL
  step {}                      │                     - Oban Triggers
     │                         │                     - Change Module
     │                         ▼                           │
     │                   1. BuildWorkflow                  │
     │                   2. IntegrateStateMachine          │
     │                   3. IntegrateOban                  │
     │                         │                           │
     │                         ▼                           │
     │                   ValidateWorkflow (Verifier)       │
     │                   (validates final DSL)             │
     │                         │                           │
     └─────────────────────────┴───────────────────────────┘
                               │
                               ▼
                    User's Action Executes
                               │
                               ▼
                    AshJobs.Change Runs
                    (after_transaction)
                               │
                     ┌─────────┴─────────┐
                     │                   │
              Success Path          Error Path
              (Change module)       (Oban trigger)
                     │                   │
                     ▼                   ▼
            Transition state      Transition state
            Schedule next job     Schedule error job
```

**Note:** ash_state_machine generates the state attribute based on the
state_machine DSL we create.

### 3.2 Module Structure with Adapters

**Following architecture-agent guidance:**

```
lib/ash_jobs/
├── ash_jobs.ex                    # Main Spark.Dsl.Extension
│
├── dsl/
│   ├── sections.ex                # Workflow section (singular)
│   └── entities/
│       └── step.ex                # Step entity schema
│
├── transformers/
│   ├── validate_workflow.ex      # Graph validation, cycle detection
│   ├── resolve_conflicts.ex      # Type-based attribute validation
│   ├── build_workflow.ex         # Change module injection
│   ├── integrate_state_machine.ex # Delegates to adapter
│   └── integrate_oban.ex         # Delegates to adapter
│
├── adapters/                      # ❌ REMOVED: No adapters in final design
│   ├── state_machine.ex          # ❌ NOT IMPLEMENTED
│   ├── state_machine/
│   │   └── ash_state_machine.ex  # ❌ NOT IMPLEMENTED
│   ├── scheduler.ex              # ❌ NOT IMPLEMENTED
│   └── scheduler/
│       └── oban_scheduler.ex     # ❌ NOT IMPLEMENTED
│
├── change.ex                      # Global routing Change module
│
├── verifiers/
│   └── workflow_consistency.ex   # Post-compilation validation
│
├── info.ex                        # Spark.InfoGenerator
├── helpers.ex                     # Operational functions
├── telemetry.ex                   # ❌ REMOVED: Use Ash/Oban telemetry instead
│
└── errors.ex                      # Custom error types
```

**Adapter Pattern (NEW - Based on senior engineering review):**

**⚠️ ENTIRE ADAPTER SECTION REMOVED:** User feedback: "wtf are the adapters
for?" - The final design uses direct integration with ash_state_machine and
ash_oban. The code below is kept for historical reference only.

```elixir
# lib/ash_jobs/adapters/state_machine.ex ❌ NOT IMPLEMENTED
defmodule AshJobs.Adapters.StateMachine do
  @moduledoc """
  Behaviour for state machine adapters.
  Allows swapping ash_state_machine for alternatives.
  """

  @callback generate_states(workflow :: map) :: [state_config :: map]
  @callback generate_transitions(workflow :: map) :: [transition_config :: map]
  @callback configure_resource(dsl_state :: term, workflow :: map) ::
    {:ok, term} | {:error, term}
end

# lib/ash_jobs/adapters/state_machine/ash_state_machine.ex
defmodule AshJobs.Adapters.StateMachine.AshStateMachine do
  @behaviour AshJobs.Adapters.StateMachine

  def generate_states(workflow) do
    # Extract all step names as states
    step_states = Enum.map(workflow.steps, & &1.name)
    terminal_states = [:completed, :failed, :cancelled]

    step_states ++ terminal_states
  end

  def generate_transitions(workflow) do
    workflow.steps
    |> Enum.flat_map(fn step ->
      [
        # Success transition
        %{
          name: :"to_#{step.on_success}",
          from: step.name,
          to: step.on_success
        },
        # Error transition (if defined)
        if step.on_error do
          %{
            name: :"to_#{step.on_error}",
            from: step.name,
            to: step.on_error
          }
        end
      ]
    end)
    |> Enum.reject(&is_nil/1)
  end

  def configure_resource(dsl_state, workflow) do
    # Use Spark.Dsl.Transformer to add state_machine section
    # with generated states and transitions
    # ...
  end
end

# lib/ash_jobs/adapters/scheduler.ex
defmodule AshJobs.Adapters.Scheduler do
  @moduledoc """
  Behaviour for job schedulers.
  Allows testing without Oban or using alternative schedulers.
  """

  @callback schedule_step(record :: term, step_name :: atom) ::
    :ok | {:error, term}
  @callback cancel_scheduled(record :: term) :: :ok | {:error, term}
end

# lib/ash_jobs/adapters/scheduler/oban_scheduler.ex
defmodule AshJobs.Adapters.Scheduler.ObanScheduler do
  @behaviour AshJobs.Adapters.Scheduler

  def schedule_step(record, step_name) do
    # Delegate to AshOban
    case AshOban.run_trigger(record, step_name) do
      {:ok, _job} -> :ok
      error -> error
    end
  end

  def cancel_scheduled(record) do
    # Cancel all pending Oban jobs for this record
    # ...
  end
end
```

**Benefits of Adapter Pattern:**

1. Testing without full Oban setup (use test adapter)
2. Future-proof for ash_state_machine API changes
3. Enables alternative schedulers (Quantum, custom solutions)
4. Reduces coupling to external dependencies

### 3.3 Data Model

**Attributes Generated:**

AshJobs does **not** generate any attributes directly. Instead:

- **State attribute:** Generated by ash_state_machine (configured via
  `state_attribute` option, defaults to `:state`)
- **Timing & error tracking:** Handled by Oban's job table (started_at,
  completed_at, errors)

Users can query job status via Oban's API or AshJobs helper functions.

**User-Defined Attributes:** Users define their own attributes for passing data
between steps:

```elixir
attribute :order_id, :uuid
attribute :calculated_total, :decimal
attribute :payment_receipt_id, :string
# ... any other data needed by workflow steps
```

**No Complex Context Management:** Unlike some workflow engines, we use simple
attributes. Data flows through the resource's attributes, validated by Ash's
type system.

### 3.4 Global Change Module Implementation

**Following elixir-expert guidance:**

```elixir
defmodule AshJobs.Change do
  @moduledoc """
  Global Change module automatically added to all workflow actions.

  Responsibilities:
  1. Detect current workflow step
  2. Transition to next state (on_success)
  3. Schedule next Oban job
  4. Emit telemetry events

  IMPORTANT: Runs in after_transaction hook, so only executes on success.
  Error routing handled by Oban trigger's on_error option.
  """
  use Ash.Resource.Change
  require Logger

  def change(changeset, _opts, _context) do
    # Detect which step this action belongs to
    resource = changeset.resource
    action_name = changeset.action.name

    case AshJobs.Info.get_step_for_action(resource, action_name) do
      nil ->
        # Not a workflow action, skip
        changeset

      step_info ->
        # This is a workflow action
        handle_workflow_step(changeset, resource, step_info)
    end
  end

  defp handle_workflow_step(changeset, resource, step_info) do
    workflow = AshJobs.Info.workflow!(resource)
    state_attr = workflow.state_attribute || :state
    next_state = step_info.on_success

    # Emit telemetry: step start
    record_id = Ash.Changeset.get_attribute(changeset, :id)
    emit_step_start(workflow, step_info.name, resource, record_id)

    changeset
    |> Ash.Changeset.force_change_attribute(state_attr, next_state)
    |> Ash.Changeset.after_transaction(fn changeset, result ->
      case result do
        {:ok, record} ->
          # Emit telemetry: step complete
          emit_step_complete(workflow, step_info.name, resource, record.id, next_state)

          # Schedule next step if not terminal
          unless next_state in [:completed, :failed, :cancelled] do
            schedule_next_step(record, next_state, workflow)
          else
            # Workflow complete
            emit_workflow_complete(workflow, resource, record.id)
          end

          {:ok, record}

        error ->
          # Transaction failed - error already handled by Oban trigger
          error
      end
    end)
  end

  defp schedule_next_step(record, step_name, _workflow) do
    # Direct call to AshOban
    case AshOban.run_trigger(record, step_name) do
      {:ok, _job} ->
        :ok
      {:error, reason} ->
        Logger.error("Failed to schedule next step: #{inspect(reason)}")
        :ok  # Don't fail the transaction
    end
  end

  # Telemetry helpers
  defp emit_step_start(workflow, step_name, resource, record_id) do
    :telemetry.execute(
      [:ash_jobs, :step, :start],
      %{system_time: System.system_time()},
      %{
        workflow: workflow.name || :default,
        step: step_name,
        resource: resource,
        record_id: record_id
      }
    )
  end

  defp emit_step_complete(workflow, step_name, resource, record_id, next_step) do
    :telemetry.execute(
      [:ash_jobs, :step, :complete],
      %{duration: 0, system_time: System.system_time()},  # Duration calculated externally
      %{
        workflow: workflow.name || :default,
        step: step_name,
        resource: resource,
        record_id: record_id,
        next_step: next_step
      }
    )
  end

  defp emit_workflow_complete(workflow, resource, record_id) do
    :telemetry.execute(
      [:ash_jobs, :workflow, :complete],
      %{total_duration: 0, step_count: 0},  # Calculated from timestamps
      %{
        workflow: workflow.name || :default,
        resource: resource,
        record_id: record_id
      }
    )
  end
end
```

**Key Design Decisions:**

1. **Runs in after_transaction:** Ensures database commit before Oban scheduling
2. **Only handles success path:** Error routing via Oban trigger (asymmetric but
   necessary)
3. **Telemetry integrated:** Production observability from day one
4. **Adapter delegation:** Uses scheduler adapter for testability
5. **Graceful degradation:** Scheduling failures don't fail the transaction

### 3.5 Transformer Pipeline Detail

**Order enforced via dependencies:**

```elixir
# lib/ash_jobs.ex
defmodule AshJobs do
  use Spark.Dsl.Extension,
    transformers: [
      AshJobs.Transformers.BuildWorkflow,
      {AshJobs.Transformers.IntegrateStateMachine,
       after: [AshJobs.Transformers.BuildWorkflow]},
      {AshJobs.Transformers.IntegrateOban,
       after: [AshJobs.Transformers.IntegrateStateMachine]}
    ],
    sections: [AshJobs.Dsl.Sections.workflow()],
    verifiers: [AshJobs.Verifiers.ValidateWorkflow]
end
```

**Transformer Responsibilities:**

**1. BuildWorkflow:**

```elixir
defmodule AshJobs.Transformers.BuildWorkflow do
  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    workflow = get_workflow(dsl_state)

    dsl_state
    |> inject_change_module(workflow)
    |> wrap_ok()
  end

  defp inject_change_module(dsl_state, workflow) do
    # Add AshJobs.Change to all workflow step actions
    workflow.steps
    |> Enum.reduce(dsl_state, fn step, acc_state ->
      add_change_to_action(acc_state, step.action, AshJobs.Change)
    end)
  end

  defp add_change_to_action(dsl_state, action_name, change_module) do
    # Use Spark.Dsl.Transformer to modify action
    # Append change module to end of changes list
    # ...
  end

  # ... helper functions
end
```

**Note:** No attribute generation - ash_state_machine handles the state
attribute based on our state_machine DSL configuration.

**2. IntegrateStateMachine:**

```elixir
defmodule AshJobs.Transformers.IntegrateStateMachine do
  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    workflow = get_workflow(dsl_state)
    state_attr = workflow.state_attribute || :state

    # Generate states: all step names + terminal states
    states =
      workflow.steps
      |> Enum.map(& &1.name)
      |> Kernel.++([:completed, :failed, :cancelled])

    # Generate transitions from on_success/on_error routing
    transitions =
      workflow.steps
      |> Enum.flat_map(&build_transitions/1)

    # Add state_machine DSL section
    dsl_state
    |> add_state_machine_section(state_attr, states, transitions)
    |> wrap_ok()
  end

  defp build_transitions(step) do
    [
      # Success transition
      %{name: :"to_#{step.on_success}", from: step.name, to: step.on_success},
      # Error transition (if defined)
      if step.on_error do
        %{name: :"to_#{step.on_error}", from: step.name, to: step.on_error}
      end
    ]
    |> Enum.reject(&is_nil/1)
  end
end
```

**3. IntegrateOban:**

```elixir
defmodule AshJobs.Transformers.IntegrateOban do
  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    workflow = get_workflow(dsl_state)
    state_attr = workflow.state_attribute || :state

    # Generate one trigger per automatic step
    triggers =
      workflow.steps
      |> Enum.reject(& &1.trigger == false)  # Skip manual steps
      |> Enum.map(&build_trigger(&1, state_attr))

    # Add triggers to oban section
    dsl_state
    |> ensure_oban_section()
    |> add_triggers(triggers)
    |> wrap_ok()
  end

  defp build_trigger(step, state_attr) do
    %Spark.Dsl.Entity{
      name: :trigger,
      target: AshOban.Trigger,
      args: [step.name],
      schema: [
        action: step.action,
        where: build_where_expr(state_attr, step.name),
        on_error: step.on_error,
        queue: step.queue || :default,
        max_attempts: step.retry_attempts || 1,
        timeout: step.timeout_seconds
      ]
    }
  end

  defp build_where_expr(state_attr, step_name) do
    quote do
      expr(unquote(state_attr) == unquote(step_name))
    end
  end
end
```

**Verifier (runs after all transformers):**

```elixir
defmodule AshJobs.Verifiers.ValidateWorkflow do
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    workflow = get_workflow(dsl_state)
    existing_attributes = Ash.Resource.Info.attributes(dsl_state.resource)
    existing_actions = Ash.Resource.Info.actions(dsl_state.resource)

    # Validate step references
    with :ok <- validate_step_references(workflow),
         :ok <- detect_circular_dependencies(workflow),
         :ok <- validate_entry_points(workflow),
         :ok <- validate_terminal_states(workflow),
         # Validate attribute types if pre-existing
         :ok <- validate_attribute_types(workflow, existing_attributes),
         # Validate user defined all required actions
         :ok <- validate_actions_exist(workflow, existing_actions),
         # Verify final DSL consistency
         :ok <- verify_state_machine_consistency(dsl_state, workflow),
         :ok <- verify_oban_consistency(dsl_state, workflow) do
      :ok
    else
      {:error, error} -> {:error, error}
    end
  end

  defp validate_step_references(workflow) do
    # Ensure all on_success/on_error targets exist
    all_steps = MapSet.new(Enum.map(workflow.steps, & &1.name))
    terminal_states = MapSet.new([:completed, :failed, :cancelled])
    valid_targets = MapSet.union(all_steps, terminal_states)

    invalid_refs =
      workflow.steps
      |> Enum.flat_map(fn step ->
        targets = [step.on_success, step.on_error, step.on_complete]
        |> Enum.reject(&is_nil/1)

        Enum.reject(targets, &MapSet.member?(valid_targets, &1))
      end)

    if Enum.empty?(invalid_refs) do
      :ok
    else
      {:error, "Invalid step references: #{inspect(invalid_refs)}"}
    end
  end

  defp detect_circular_dependencies(workflow) do
    # Build dependency graph and detect cycles using DFS
    graph = build_dependency_graph(workflow)

    case find_cycle(graph) do
      nil -> :ok
      cycle -> {:error, "Circular dependency detected: #{inspect(cycle)}"}
    end
  end

  defp validate_attribute_types(workflow, existing_attributes) do
    state_attr = workflow.state_attribute || :state

    # Check state attribute type
    case find_attribute(existing_attributes, state_attr) do
      nil -> :ok  # Will be generated
      %{type: :atom} -> :ok  # Correct type
      %{type: other_type} ->
        {:error, "State attribute '#{state_attr}' has wrong type. Expected :atom, got #{inspect(other_type)}"}
    end
  end

  defp validate_actions_exist(workflow, existing_actions) do
    # Validate user has defined all step actions
    missing_actions =
      workflow.steps
      |> Enum.reject(fn step ->
        Enum.any?(existing_actions, &(&1.name == step.action))
      end)
      |> Enum.map(& &1.action)

    if Enum.empty?(missing_actions) do
      :ok
    else
      {:error, "Missing required actions: #{inspect(missing_actions)}. Define these actions in your resource."}
    end
  end

  # ... other validation functions
end
```

---

## 4. Integration Strategy

### 4.1 Third-Party Integration - Oban

**Current Status:** NEW INTEGRATION

**Integration Approach:**

1. Users install Oban via mix dependency
2. Users run Oban migrations
3. AshJobs generates Oban triggers via transformer
4. AshJobs.Change schedules jobs via adapter

**Configuration Required:**

```elixir
# config/config.exs
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [
    default: 10,
    order_processing: 20,
    payment_processing: 10,
    shipping_processing: 10
  ],
  plugins: [
    Oban.Plugins.Pruner,
    Oban.Plugins.Stager
  ]

# Application supervision tree
def start(_type, _args) do
  children = [
    MyApp.Repo,
    {Oban, Application.fetch_env!(:my_app, Oban)},
    # ...
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

**Error Handling:**

- Oban retries configured per-step via `retry_attempts` option
- On final failure, Oban trigger's `on_error` routes to error handler step
- Error details stored in `last_error` attribute

**Testing Support:**

```elixir
# In test environment
config :my_app, Oban, testing: :manual

# Or for inline execution
use Oban.Testing, repo: MyApp.Repo

test "workflow executes all steps" do
  Oban.Testing.with_testing_mode(:inline) do
    job = create_fulfillment_job(state: :load_order)

    # Triggers fire synchronously in inline mode
    assert_receive {:oban_job_executed, _}

    updated = reload(job)
    assert updated.state == :completed
  end
end
```

### 4.2 Third-Party Integration - ash_state_machine

**Current Status:** NEW INTEGRATION

**Integration Approach:**

1. AshJobs generates `state_machine` DSL section
2. Each workflow step becomes a state
3. Transitions generated from `on_success`/`on_error` routing
4. Terminal states: `:completed`, `:failed`, `:cancelled`

**Compatibility Note:** ash_state_machine only supports one state machine per
resource. This is WHY we recommend separate job resources (FulfillmentJob,
ReturnJob) rather than multiple workflows on domain entities.

**Generated State Machine:**

```elixir
# What AshJobs generates
state_machine do
  initial_states [:load_order]
  default_initial_state :load_order
  state_attribute :state

  transitions do
    # Generated from workflow steps
    transition :to_validate_inventory,
      from: :load_order,
      to: :validate_inventory

    transition :to_calculate_total,
      from: :validate_inventory,
      to: :calculate_total

    # Terminal transitions
    transition :to_completed,
      from: :mark_complete,
      to: :completed

    transition :to_failed,
      from: :refund_and_notify,
      to: :failed
  end
end
```

**State Chart Support:** Users can visualize workflows using ash_state_machine's
built-in Mermaid diagram generation.

### 4.3 Database Requirements

**PostgreSQL:** Required for Oban's job queue table.

**Migrations:**

```bash
# 1. Oban migration (generated by mix ash_jobs.install)
mix ecto.gen.migration add_oban_jobs_table

# In migration:
defmodule MyApp.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 12)
  end

  def down do
    Oban.Migration.down(version: 12)
  end
end

# 2. Workflow attributes migration (generated by mix ash_jobs.install)
mix ecto.gen.migration add_workflow_attrs_to_fulfillment_jobs

# In migration:
defmodule MyApp.Repo.Migrations.AddWorkflowAttrsToFulfillmentJobs do
  use Ecto.Migration

  def change do
    alter table(:fulfillment_jobs) do
      add :state, :string, null: false, default: "load_order"
    end

    create index(:fulfillment_jobs, [:state])
  end
end

# Note: Workflow timing and errors tracked in Oban's jobs table
```

**Performance Considerations:**

- Add index on state attribute for Oban trigger queries
- Consider partitioning workflow tables by date for high-volume workflows
- Monitor Oban job queue table size (use Pruner plugin)

---

## 5. Agent Consultations & Recommendations

### 5.1 Architecture Agent Findings

**Module Structure Validation:** ✅ APPROVED

- Transformer ordering is sound
- Separation of concerns is clear
- Adapter pattern provides future flexibility

**Critical Recommendations:**

1. Use `before:` and `after:` transformer dependencies
2. Isolate integration code behind adapter interfaces
3. Comprehensive integration test suite required

**Testing Structure:**

```
test/
├── unit/
│   ├── transformers/          # Transformer-specific tests
│   ├── adapters/               # Adapter behavior tests
│   └── helpers/                # Helper function tests
├── integration/
│   ├── workflow_execution_test.exs
│   ├── manual_steps_test.exs
│   └── error_handling_test.exs
└── support/
    ├── test_resources.ex      # Sample resources
    └── test_helpers.ex        # Shared utilities
```

### 5.2 Elixir Expert Findings

**Spark DSL Patterns:** ✅ VALIDATED

- Transformer dependencies enforce ordering
- Ash.Resource.Builder for safe attribute generation
- Verifiers for post-compilation validation

**Critical Recommendations:**

1. **Global Change Module:**

   ```elixir
   # Use after_transaction for Oban scheduling
   Ash.Changeset.after_transaction(changeset, fn changeset, result ->
     case result do
       {:ok, record} -> schedule_next_step(record)
       error -> error
     end
   end)
   ```

2. **Manual Pause Points:**

   ```elixir
   # Provide clear API for manual advancement
   AshJobs.advance_workflow(resource, record_id, :step_name)
   ```

3. **Testing Approaches:**
   ```elixir
   # Use Oban.Testing for synchronous execution
   Oban.Testing.with_testing_mode(:inline) do
     # Test workflow execution
   end
   ```

**Common Pitfalls Identified:**

- Not declaring transformer dependencies → race conditions
- Forgetting `after_transaction` → jobs scheduled in transaction
- No telemetry → production debugging nightmare

### 5.3 Senior Engineering Review Findings

**Strategic Assessment:** ⚠️ CONCERNS WITH MITIGATION OPPORTUNITIES

**Scale Targets:**

- **10x (1,000 workflows/min):** ✅ Feasible with proper queue configuration
- **100x (10,000 workflows/min):** ⚠️ Requires architectural changes

**Critical Recommendations for v0.1.0:**

1. **Include Migration Generator:** MANDATORY for adoption

   ```bash
   mix ash_jobs.install --resource MyApp.FulfillmentJob
   ```

2. **Include Operational Helpers:** MANDATORY for production

   ```elixir
   AshJobs.get_workflow_status(resource, id)
   AshJobs.retry_workflow(resource, id, from_step: :step_name)
   AshJobs.cancel_workflow(resource, id, reason: "...")
   ```

3. **Include Basic Telemetry:** MANDATORY for debugging

   ```elixir
   [:ash_jobs, :step, :complete]
   [:ash_jobs, :workflow, :complete]
   ```

**Technical Debt Identified:**

1. **Error Routing Asymmetry:**

   - Success: Handled by Change module
   - Error: Handled by Oban trigger
   - **Mitigation:** Document clearly, plan unified routing for v0.2.0

2. **One Workflow Per Resource Limitation:**

   - Consequence of ash_state_machine architecture
   - **Mitigation:** Document pattern, require separate job resources

3. **No Built-in History Tracking:**
   - Users can't see workflow execution history
   - **Mitigation:** Defer to v0.2.0, document workarounds

**Scale Limit Documentation:**

```markdown
## Supported Scale

**v0.1.0 Targets:**

- Up to 1,000 workflows/minute per node
- Average 4-6 steps per workflow
- Database: PostgreSQL with proper indexing

**Performance Tuning:**

- Connection pool: `workflows_per_min * 2.5`
- Oban queue concurrency: `(jobs_per_sec * avg_duration_sec) * 1.5`
- Separate queues for different workflow types

**100x Scale (10,000+ workflows/min):**

- Requires Oban Smart Engine (Oban Pro)
- Consider workflow state partitioning
- Consider event sourcing for state storage
```

---

## 6. Implementation Phases

### Phase 1: Foundation - DSL & Core Transformers (Week 1-2)

**Goal:** Working DSL with Change module injection

**Deliverables:**

- [ ] `lib/ash_jobs.ex` - Main Spark extension
- [ ] `lib/ash_jobs/dsl/sections.ex` - Workflow section
- [ ] `lib/ash_jobs/dsl/entities/step.ex` - Step entity
- [ ] `lib/ash_jobs/transformers/build_workflow.ex`
- [ ] `lib/ash_jobs/verifiers/validate_workflow.ex`
- [ ] Unit tests for transformer and verifier
- [ ] Basic documentation

**Success Criteria:**

- DSL compiles without errors
- Change module injection works correctly
- Validation catches invalid configurations

### Phase 2: Integration (Week 3)

**Goal:** State machine and Oban integration

**Deliverables:**

- [ ] `lib/ash_jobs/transformers/integrate_state_machine.ex`
- [ ] `lib/ash_jobs/transformers/integrate_oban.ex`
- [ ] Integration tests

**Success Criteria:**

- State machine DSL generated correctly
- Oban triggers generated correctly
- End-to-end workflow compiles

### Phase 3: Routing & Execution (Week 4)

**Goal:** Working workflow execution

**Deliverables:**

- [ ] `lib/ash_jobs/change.ex` - Global Change module
- [ ] `lib/ash_jobs/telemetry.ex` - Event instrumentation
- [ ] `lib/ash_jobs/info.ex` - Introspection module
- [ ] Integration tests with real Oban execution
- [ ] Test manual pause points
- [ ] Test error handling and routing

**Success Criteria:**

- Workflows execute end-to-end
- State transitions work correctly
- Next steps scheduled automatically
- Manual steps work correctly
- Telemetry events emitted

### Phase 4: Operational Tooling (Week 5) - CRITICAL

**Goal:** Production-ready operational tools

**Deliverables:**

- [ ] `lib/ash_jobs/helpers.ex` - Operational functions
  - [ ] `get_workflow_status/2`
  - [ ] `retry_workflow/3`
  - [ ] `cancel_workflow/3`
  - [ ] `advance_workflow/3` (manual steps)
  - [ ] `list_workflows_in_state/2`
  - [ ] `detect_stuck_workflows/2`
- [ ] `lib/mix/tasks/ash_jobs.install.ex` - Migration generator
- [ ] Comprehensive error messages
- [ ] Production runbook documentation

**Success Criteria:**

- Migration generator works for new projects
- Helper functions cover common operations
- Clear error messages for all failure modes
- Operations documentation complete

### Phase 5: Documentation & Polish (Week 6)

**Goal:** Production-ready release

**Deliverables:**

- [ ] Complete API documentation (ExDoc)
- [ ] Getting Started guide
- [ ] Production deployment guide
- [ ] Performance tuning guide
- [ ] Troubleshooting runbook
- [ ] Example projects
- [ ] Scale limit documentation
- [ ] Migration guide from manual patterns

**Success Criteria:**

- All public functions documented
- Users can get started in <30 minutes
- Production deployment clearly documented
- Scale limits explicitly stated

---

## 7. Quality & Testing Strategy

### 7.1 Test Coverage Goals

**Target:** 95%+ test coverage with focus on critical paths

**Test Breakdown:**

**Unit Tests (80+ tests):**

- Transformer correctness (50 tests)
  - BuildWorkflow: 20 tests
  - IntegrateStateMachine: 15 tests
  - IntegrateOban: 15 tests
- Verifier validation (20 tests)
- Helper functions (10 tests)

**Integration Tests (50+ tests):**

- End-to-end workflows (20 tests)
  - Success paths
  - Error paths
  - Manual steps
  - Retry logic
- State machine integration (10 tests)
- Oban integration (10 tests)
- Adapter behavior (10 tests)

**Property-Based Tests (Recommended):**

```elixir
# Use StreamData for workflow validation
property "all steps reachable from entry point" do
  check all workflow <- workflow_generator() do
    reachable_steps = compute_reachable(workflow)
    all_steps = MapSet.new(Enum.map(workflow.steps, & &1.name))

    assert MapSet.equal?(reachable_steps, all_steps)
  end
end

property "no circular dependencies" do
  check all workflow <- workflow_generator() do
    refute has_cycle?(workflow)
  end
end
```

### 7.2 Performance Testing

**Metrics to Track:**

1. Workflow execution duration
2. Step execution duration
3. Database query count per step
4. Oban job queue depth
5. Connection pool utilization

**Load Testing Scenarios:**

```elixir
# Simulate 1,000 workflows/min
defmodule AshJobs.LoadTest do
  def run_load_test(duration_seconds) do
    workflows_per_second = 16  # ~1000/min

    for _ <- 1..duration_seconds do
      Task.async_stream(
        1..workflows_per_second,
        fn _ -> create_and_execute_workflow() end,
        max_concurrency: 100
      )
      |> Stream.run()

      :timer.sleep(1000)
    end

    collect_metrics()
  end
end
```

**Performance Benchmarks:**

- Workflow creation: <10ms
- Step transition: <5ms
- Oban job scheduling: <20ms
- End-to-end 4-step workflow: <500ms (excluding business logic)

### 7.3 Quality Gates

**Pre-Commit:**

- `mix format --check-formatted`
- `mix credo --strict`
- `mix dialyzer` (after initial PLT build)

**CI Pipeline:**

1. Compile with warnings as errors
2. Run all tests
3. Check test coverage (>95%)
4. Run Credo
5. Run Dialyzer
6. Build documentation
7. Check for documentation warnings

**Pre-Release:**

1. All CI checks pass
2. Integration tests pass with real Oban
3. Example projects work end-to-end
4. Documentation reviewed
5. CHANGELOG.md updated

---

## 8. Risk Assessment & Mitigation

### 8.1 High-Priority Risks

**Risk 1: ash_state_machine Breaking Changes**

**Probability:** Medium (Ash ecosystem evolving rapidly) **Impact:** High (Core
integration dependency)

**Mitigation Strategy:**

1. ✅ Adapter abstraction isolates dependency
2. ✅ Pin exact minor versions in v0.1.0
3. ✅ Comprehensive integration tests catch API changes
4. Plan version-specific adapters if needed:
   ```elixir
   case ash_state_machine_version() do
     %{major: 0, minor: 2} -> AshJobs.Adapters.StateMachine.V0_2
     %{major: 0, minor: 3} -> AshJobs.Adapters.StateMachine.V0_3
   end
   ```

**Risk 2: Conflict with Other Extensions**

**Probability:** Medium (Users may already use ash_state_machine) **Impact:**
High (Blocks adoption)

**Scenario:**

```elixir
# User has existing state machine
defmodule Order do
  use Ash.Resource,
    extensions: [AshStateMachine]  # Already using for order status

  state_machine do
    # Existing state machine for order workflow
  end
end

# Now wants to add AshJobs
extensions: [AshJobs, AshStateMachine]  # CONFLICT!
```

**Mitigation Strategy:**

1. ✅ Document "separate job resources" pattern clearly
2. ✅ Detect conflicts in ResolveConflicts transformer
3. ✅ Provide clear error messages with migration guide:

   ```
   Error: Cannot use AshJobs on resources with existing state_machine.

   Solution: Create a separate job resource:

   defmodule FulfillmentJob do
     use Ash.Resource, extensions: [AshJobs, AshStateMachine, AshOban]

     relationships do
       belongs_to :order, Order
     end

     workflow do
       # Your workflow steps
     end
   end
   ```

**Risk 3: Database Performance at Scale**

**Probability:** Medium-High (Depends on user scale) **Impact:** High
(Production performance issues)

**Bottlenecks Identified:**

- State attribute updates (write amplification)
- Oban job queue queries (lock contention)
- Connection pool exhaustion

**Mitigation Strategy:**

1. ✅ Document scale limits explicitly (1,000 workflows/min)
2. ✅ Provide performance tuning guide
3. ✅ Include telemetry for monitoring
4. ✅ Recommend indexes in migration generator:
   ```elixir
   create index(:fulfillment_jobs, [:state])
   create index(:fulfillment_jobs, [:started_at])
   ```
5. Future: Event sourcing option (v0.3.0)

**Risk 4: Complex Debugging in Production**

**Probability:** High (Complex distributed systems are hard to debug)
**Impact:** Medium (User frustration, support burden)

**Scenarios:**

- "My workflow is stuck"
- "Why did my workflow fail?"
- "How do I retry a failed workflow?"

**Mitigation Strategy:**

1. ✅ Operational helper functions (get_status, retry, cancel)
2. ✅ Telemetry events for observability
3. ✅ Structured error context in `last_error` field
4. ✅ Troubleshooting runbook documentation
5. Consider: Workflow execution log table (v0.2.0)

### 8.2 Medium-Priority Risks

**Risk 5: User Adoption Friction**

**Probability:** Medium **Impact:** High (Low adoption)

**Friction Points:**

- Complex setup (Oban migration, config, supervision tree)
- Unfamiliar DSL concepts
- Migration from existing patterns

**Mitigation Strategy:**

1. ✅ Migration generator (`mix ash_jobs.install`)
2. ✅ Comprehensive getting started guide
3. ✅ Example projects
4. ✅ Video tutorial (future)
5. Active community support (Discord, GitHub discussions)

**Risk 6: Test Complexity**

**Probability:** High (200+ tests planned) **Impact:** Medium (Maintenance
burden)

**Challenges:**

- Testing transformer code generation
- Integration tests with Oban require database
- Flaky tests with async execution

**Mitigation Strategy:**

1. ✅ Use Oban.Testing for synchronous execution
2. ✅ Property-based testing for transformers
3. ✅ Clear test organization (unit vs integration)
4. ✅ Mock adapters for unit tests
5. CI pipeline with proper database setup

---

## 9. Success Criteria

### v0.1.0 Release Criteria

**Functional Requirements:**

- ✅ DSL compiles and generates correct code
- ✅ Workflows execute end-to-end
- ✅ State transitions work correctly
- ✅ Oban triggers fire and schedule next steps
- ✅ Manual pause points work correctly
- ✅ Error handling and routing work correctly
- ✅ Retry logic works as configured

**Operational Requirements:**

- ✅ Migration generator works (`mix ash_jobs.install`)
- ✅ Helper functions cover common operations
- ✅ Telemetry events emitted correctly
- ✅ Stuck workflow detection works
- ✅ Workflow retry/cancel works
- ✅ Clear error messages for all failure modes

**Quality Requirements:**

- ✅ 95%+ test coverage
- ✅ All CI checks pass (format, credo, dialyzer)
- ✅ No compiler warnings
- ✅ Documentation complete for all public functions
- ✅ Getting started guide complete
- ✅ Example projects work

**Performance Requirements:**

- ✅ Supports 1,000 workflows/min
- ✅ <10ms workflow creation overhead
- ✅ <5ms step transition overhead
- ✅ Load testing validates performance

### Production Readiness Checklist

**Before First Production Deployment:**

- [ ] Database migrations run successfully
- [ ] Oban configured with appropriate queues
- [ ] Connection pool sized correctly
- [ ] Indexes created on state columns
- [ ] Telemetry monitoring configured
- [ ] Stuck workflow alerts configured
- [ ] Backup/restore procedures tested
- [ ] Runbook reviewed by operations team

---

## 10. Future Roadmap (Post v0.1.0)

### v0.2.0 - Operational Excellence (3-6 months)

**Goals:** Production hardening and observability

**Features:**

- [ ] Unified error routing in Global Change module
- [ ] Workflow execution history tracking
- [ ] Automatic stuck workflow detection and alerts
- [ ] Performance profiling tools
- [ ] Workflow visualization (Mermaid diagrams)
- [ ] Advanced telemetry dashboards
- [ ] Workflow versioning support

**Technical Debt Paydown:**

- Resolve error routing asymmetry
- Add typed context schemas (optional)
- Improve transformer performance

### v0.3.0 - Architectural Evolution (6-12 months)

**Goals:** Flexibility and scale

**Features:**

- [ ] Parallel step execution support
- [ ] Multi-way conditional branching
- [ ] Nested/composed workflows
- [ ] Compensation/saga patterns
- [ ] Event sourcing option for state storage
- [ ] Support coexisting with ash_state_machine
- [ ] Alternative scheduler adapters (Quantum)

**Scale Improvements:**

- Target 10,000+ workflows/min
- Workflow state partitioning
- Distributed coordination

### v0.4.0 - Ecosystem Integration (12+ months)

**Goals:** Become standard workflow solution for Ash

**Features:**

- [ ] Phoenix LiveView workflow dashboard
- [ ] Workflow analytics and reporting
- [ ] Workflow templates/blueprints
- [ ] Dynamic workflow generation
- [ ] Workflow marketplace
- [ ] Integration with Ash authentication
- [ ] Multi-tenancy support

---

## 11. Documentation Strategy

### User-Facing Documentation

**1. README.md:**

- Quick overview and value proposition
- Installation instructions (with migration generator)
- Basic usage example
- Links to comprehensive docs

**2. Getting Started Guide:**

- Complete tutorial building a simple workflow
- Explanation of key concepts
- Common patterns and best practices
- Migration from manual Oban patterns

**3. API Reference:**

- Generated via ExDoc
- All public functions documented
- Module-level overview documentation
- Code examples for all major functions

**4. Production Deployment Guide:**

- Database setup and migrations
- Oban configuration recommendations
- Performance tuning guide
- Scale limits and when to optimize
- Monitoring and observability setup

**5. Troubleshooting Runbook:**

- Common issues and solutions
- Debugging workflows (stuck, failed, slow)
- Recovery procedures
- Performance optimization
- Database maintenance

**6. Design Decisions Document:**

- Architectural rationale
- Trade-offs and alternatives considered
- Scale limitations and why
- Future roadmap

### Developer-Facing Documentation

**1. Contributing Guide:**

- Development setup
- Running tests
- Code style guidelines
- Pull request process

**2. Architecture Documentation:**

- Transformer pipeline explanation
- DSL design decisions
- Adapter system
- Extension points

**3. Testing Guide:**

- Test organization
- How to test transformers
- Integration test patterns
- Property-based testing examples

---

## 12. Strategic Guidance Summary

### Key Architectural Decisions

**1. One Workflow Per Resource**

- **Rationale:** ash_state_machine limitation
- **Pattern:** Separate job resources (FulfillmentJob, ReturnJob)
- **Trade-off:** More resources, but clearer separation of concerns

**2. Sequential Execution Only (v0.1.0)**

- **Rationale:** Solves 80% of use cases with 20% of complexity
- **Pattern:** Explicit routing via on_success/on_error
- **Trade-off:** No parallel execution, but simpler implementation

**3. Global Change Module**

- **Rationale:** Single routing logic, easier to maintain
- **Pattern:** Automatically added to all workflow actions
- **Trade-off:** Less granular control, but consistent behavior

**4. Adapter Abstractions**

- **Rationale:** Future-proof against dependency changes
- **Pattern:** Behaviour modules for state machine and scheduler
- **Trade-off:** Extra layer of indirection, but flexibility

**5. Telemetry from Day One**

- **Rationale:** Production observability is not optional
- **Pattern:** Emit events for all workflow operations
- **Trade-off:** Slightly more code, but huge operational value

### Critical Success Factors

**Must Have for v0.1.0:**

1. ✅ Migration generator - dramatically lowers adoption barrier
2. ✅ Operational helpers - makes production deployments safe
3. ✅ Telemetry - enables debugging and optimization
4. ✅ Adapter abstractions - future-proofs architecture
5. ✅ Clear documentation - reduces support burden

**Must Document:**

1. Scale limits (1,000 workflows/min for v0.1.0)
2. Separate job resources pattern (not obvious to users)
3. Error routing split (asymmetry causes confusion)
4. Performance tuning recommendations
5. Troubleshooting procedures

**Must Defer to v0.2.0+:**

1. Parallel execution (complex, low demand)
2. Workflow history (valuable but not blocking)
3. Compensation patterns (advanced use case)
4. Workflow versioning (premature optimization)

---

## Next Steps

### Immediate Actions

1. **User Review & Approval:**

   - Review this strategic plan
   - Confirm v0.1.0 scope decisions
   - Approve inclusion of operational tooling
   - Confirm scale targets and limitations

2. **Architecture Validation:**

   - Validate adapter pattern approach
   - Confirm transformer pipeline design
   - Review Global Change module implementation

3. **Proceed to Breakdown Phase:**
   - Create detailed task breakdown
   - Define implementation checklist
   - Establish development milestones

### Ready for Breakdown Phase

This strategic implementation plan transforms the research into actionable
architecture with:

- ✅ Complete feature specifications
- ✅ Technical design with code examples
- ✅ Integration patterns defined
- ✅ Risk mitigation strategies
- ✅ Quality standards established
- ✅ Expert consultations integrated
- ✅ Production readiness criteria
- ✅ Clear success metrics

**Next Command:** `/breakdown ash jobs` to create detailed implementation task
list.

---

**Plan Created By:** Implementation Planner **Expert Consultations:**

- ✅ architecture-agent: Module structure and integration patterns
- ✅ elixir-expert: Spark DSL patterns and Ash conventions
- ✅ senior-engineer-reviewer: Strategic validation and long-term sustainability

**Confidence Level:** HIGH - Comprehensive strategic foundation with expert
validation and clear implementation path.
