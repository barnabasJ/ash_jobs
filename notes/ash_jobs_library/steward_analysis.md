# Steward Jobs Analysis & DSL Options

**Date:** 2025-10-13

---

## Current Steward Pattern Analysis

### Architecture Overview

**Two-Level State Machine:**

```elixir
# Top-level Job resource
state: :pending | :processing | :completed | :failed | :cancelled

# Embedded MessageMove details
substate: :awaiting_range_end | :pending | :awaiting_confirmation |
          :analyzed | :webhook_ready | :moved | :completed | :failed
```

**Key Characteristics:**

1. **Sequential execution** - one step at a time, no parallelism
2. **State-based triggers** - Oban filters on `state + type + substate`
3. **Explicit chaining** - each action calls `run_oban_trigger(:next_step)`
4. **User interaction points** - workflow pauses for external input
5. **Granular error handling** - each step has dedicated error action
6. **Change modules** - business logic in separate modules
7. **Manual state management** - Change modules update embedded state

### Message Move Workflow

**6 Phases:**

```
1. awaiting_range_end → User selects message range
2. pending → AI analyzes messages
3. awaiting_confirmation → User confirms selection
4. analyzed → Prepare Discord webhooks
5. webhook_ready → Move messages
6. moved → Cleanup
7. completed → Notify completion
```

**Oban Trigger Pattern:**

```elixir
trigger :analyze_messages do
  action :analyze_messages
  where expr(state == :pending and type == :message_move and substate == :pending)
  on_error :handle_analysis_error
  queue :message_processing
end

trigger :send_confirmation do
  action :send_confirmation
  where expr(state == :processing and type == :message_move and substate == :awaiting_confirmation)
  queue :message_sending
end
```

**Action Pattern:**

```elixir
update :analyze_messages do
  accept []
  require_atomic? false
  change AnalyzeMessages  # Business logic in Change module
  change run_oban_trigger(:send_confirmation)  # Explicit next step
end

update :handle_analysis_error do
  argument :error, :map, allow_nil?: false
  accept []
  require_atomic? false
  change HandleAnalysisError  # Error-specific logic
end
```

**Change Module Pattern:**

```elixir
defmodule AnalyzeMessages do
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    # 1. Validate job state
    # 2. Perform business logic (query messages, call AI, etc.)
    # 3. Update embedded details state: details.state = :awaiting_confirmation
    # 4. Return updated changeset
    changeset
    |> Ash.Changeset.force_change_attribute(:details, updated_details)
    |> Ash.Changeset.force_change_attribute(:state, :processing)
  end
end
```

---

## Key Observations

### What Works Well

1. **Clear state progression** - easy to understand where workflow is
2. **Explicit control flow** - no magic, each step schedules next
3. **Fine-grained error handling** - each step has dedicated error path
4. **User interaction support** - workflow naturally pauses
5. **Type safety** - enum states prevent typos
6. **Testability** - Change modules are pure functions
7. **Flexibility** - full control over state transitions

### Pain Points

1. **Boilerplate heavy** - each step needs:

   - Action definition
   - Change module file
   - Error handler action
   - Error handler Change module
   - Oban trigger with complex filter
   - Manual `run_oban_trigger` calls

2. **State management complexity**:

   - Two levels of state (generic + specific)
   - Manual state transitions in Change modules
   - Oban filters must know about state structure

3. **Implicit dependencies**:

   - Step order defined by `run_oban_trigger` calls
   - Easy to miss scheduling next step
   - No compile-time validation of step chains

4. **Repetitive patterns**:

   - Every step follows same structure
   - Error handlers all look similar
   - Oban trigger definitions very similar

5. **No automatic progression**:

   - Must remember to call `run_oban_trigger`
   - Easy to create "stuck" workflows

6. **Scattered workflow logic**:
   - Workflow spread across: triggers, actions, Change modules
   - Hard to see full workflow in one place

---

## Requirements Derived from Steward

### Must Support

1. **User interaction pauses**

   - Workflow waits for external input (user confirmation, webhooks, etc.)
   - External code can advance workflow via actions

2. **Sequential execution**

   - Steps run one at a time
   - Each step completes before next starts

3. **Complex business logic**

   - Change modules with full Ash/Ecto access
   - Database queries, external API calls
   - Multi-step transformations

4. **Granular error handling**

   - Per-step error actions
   - Error details preserved
   - Recovery/retry options

5. **State introspection**

   - Know current step from outside
   - Query jobs by current step
   - Display progress to users

6. **Multiple queue support**
   - Different steps in different queues
   - Priority control per step

### Nice to Have

1. **Conditional branching**

   - Skip steps based on conditions
   - Different paths for different scenarios

2. **Subworkflows/composition**

   - Reusable workflow segments
   - Nested workflows

3. **Compensating actions**
   - Rollback on failure
   - Cleanup after errors

---

## DSL Option 1: Explicit State-Based (Minimal Change from Current)

**Philosophy:** Keep current approach but reduce boilerplate

```elixir
use Ash.Resource,
  extensions: [AshJobs, AshStateMachine, AshOban]

workflows do
  workflow :message_move do
    # Still uses embedded resource for details
    details_type MessageMove

    # Define states explicitly
    states do
      state :awaiting_range_end, initial: true
      state :pending
      state :awaiting_confirmation, pausable: true
      state :analyzed
      state :webhook_ready
      state :moved
      state :completed, terminal: true
      state :failed, terminal: true
    end

    # Define steps with their state transitions
    step :analyze_messages do
      from_state :pending
      to_state :awaiting_confirmation
      on_error :handle_analysis_error
      queue :message_processing

      # Change module handles logic
      change AnalyzeMessages
    end

    step :send_confirmation do
      from_state :awaiting_confirmation
      # No to_state means it stays in same state (waiting for user)
      queue :message_sending
    end

    # User actions that advance state
    action :confirm_move do
      from_state :awaiting_confirmation
      to_state :analyzed
      triggers_step :prepare_webhooks
    end

    step :prepare_webhooks do
      from_state :analyzed
      to_state :webhook_ready
      on_error :handle_webhook_error
      queue :message_processing
      change PrepareWebhooks
    end

    # ... more steps
  end
end

# Generated automatically:
# - Oban triggers with proper state filters
# - Error handler actions
# - State transition validations
# - run_oban_trigger calls in actions
```

**Pros:**

- Familiar to current steward pattern
- Clear state machine visualization
- Supports user interaction naturally
- Minimal learning curve

**Cons:**

- Still requires separate Change modules
- State management still manual in Change modules
- Not much simpler than current approach

---

## DSL Option 2: Dependency-Based with Pause Points (Hybrid Reactor)

**Philosophy:** Use Reactor-style dependencies but support pausing

```elixir
workflows do
  workflow :message_move do
    # Steps declare dependencies, not states
    # Execution waits for dependencies to complete

    step :await_range_end do
      # No arguments - workflow starts here
      # Pausable means external code must complete it
      pausable true
      completion_action :mark_range_end_and_move
    end

    step :analyze_messages do
      action :analyze_messages
      # Depends on range end being marked
      argument :start_id, result(:await_range_end, [:start_message_discord_id])
      argument :end_id, result(:await_range_end, [:end_message_discord_id])
      on_error :handle_analysis_error
      queue :message_processing
    end

    step :await_confirmation do
      # Pauses workflow for user input
      pausable true
      # Depends on analysis completing
      argument :messages, result(:analyze_messages, [:messages_to_move])
      completion_actions [:confirm_move, :cancel_move]
    end

    step :prepare_webhooks do
      action :prepare_webhooks
      # Only runs after user confirms
      argument :destination, result(:await_confirmation, [:destination_channel_id])
      on_error :handle_webhook_error
      queue :message_processing
    end

    step :move_messages do
      action :move_messages
      argument :webhook_id, result(:prepare_webhooks, [:webhook_id])
      argument :webhook_token, result(:prepare_webhooks, [:webhook_token])
      argument :messages, result(:analyze_messages, [:messages_to_move])
      queue :message_processing
    end

    # ... more steps
  end
end

# State tracked automatically based on completed steps
# No manual state transitions in Change modules
# Steps execute when dependencies satisfied
```

**Pros:**

- Dependencies are explicit
- Less boilerplate (no manual state management)
- Flexible - can easily reorder steps
- Supports pausing naturally

**Cons:**

- Pausable steps complicate dependency graph
- Less obvious where workflow currently is
- More complex implementation
- Parallel execution concerns (addressed via sequential flag)

---

## DSL Option 3: Linear Pipeline with Markers (Simplest)

**Philosophy:** Workflows are linear pipelines with explicit pause/branch points

```elixir
workflows do
  workflow :message_move do
    # Steps execute in order, one at a time
    sequential true  # No parallelism

    # Pause points - wait for external completion
    pause :await_range_end do
      completion_action :mark_range_end_and_move
    end

    # Regular step
    step :analyze_messages do
      action :analyze_messages
      on_error :handle_analysis_error
      queue :message_processing
    end

    # Another pause
    pause :await_confirmation do
      completion_actions [:confirm_move, :cancel_move]
      cancel_action :cancel_move
    end

    step :prepare_webhooks do
      action :prepare_webhooks
      on_error :handle_webhook_error
      queue :message_processing
    end

    step :move_messages do
      action :move_messages
      queue :message_processing
    end

    step :cleanup do
      action :cleanup_operation
    end

    step :notify do
      action :notify_completion
    end
  end
end

# Generated:
# - Sequential execution (step runs when previous completes)
# - Pause points generate special "waiting" substates
# - Each step gets Oban trigger
# - Error handlers auto-generated
# - Context map tracks progress: {current_step, completed_steps, results}
```

**Pros:**

- **Simplest mental model** - just a list of steps
- Minimal boilerplate
- Order is explicit and visual
- Natural fit for sequential workflows
- Easy to understand current position

**Cons:**

- No support for parallel execution
- Limited flexibility (can't easily reorder)
- Pause points feel like special case

---

## DSL Option 4: State Machine First (Most Explicit)

**Philosophy:** Embrace state machine, make it ergonomic

```elixir
workflows do
  workflow :message_move do
    # Define all states first
    states do
      state :awaiting_range_end, initial: true
      state :analyzing
      state :awaiting_confirmation
      state :preparing_webhooks
      state :moving_messages
      state :cleaning_up
      state :completed, terminal: true
      state :failed, terminal: true
    end

    # Steps are state transitions with actions
    transition :start_analysis do
      from :awaiting_range_end
      to :analyzing
      # Triggered by external action
      triggered_by_action :mark_range_end_and_move
    end

    transition :analyze do
      from :analyzing
      to :awaiting_confirmation
      action :analyze_messages
      on_error :failed
      oban queue: :message_processing, max_attempts: 3
    end

    transition :user_confirms do
      from :awaiting_confirmation
      to :preparing_webhooks
      triggered_by_action :confirm_move
    end

    transition :user_cancels do
      from :awaiting_confirmation
      to :failed
      triggered_by_action :cancel_move
    end

    transition :prepare_webhooks do
      from :preparing_webhooks
      to :moving_messages
      action :prepare_webhooks
      on_error :failed
    end

    # ... more transitions
  end
end

# Generated:
# - AshStateMachine configuration
# - Oban triggers for automated transitions
# - Action hooks for user transitions
# - State validation
```

**Pros:**

- **Most explicit** - every transition documented
- Strong state machine semantics
- Easy to validate correctness
- Clear separation: automated vs user-triggered

**Cons:**

- Most verbose
- Requires thinking in state machine terms
- Harder to see "happy path" flow

---

## DSL Option 5: Hybrid - Steps with Explicit Control

**Philosophy:** Steps are primary, but with explicit control flow

```elixir
workflows do
  workflow :message_move do
    # Context tracked automatically
    context_schema do
      field :start_message_id, :integer
      field :end_message_id, :integer
      field :messages_to_move, {:array, :uuid}
      field :webhook_id, :string
      field :webhook_token, :string
      field :destination_channel_id, :integer
    end

    # Entry point
    step :await_range_end do
      # Pausable step - waits for external trigger
      type :manual
      completion_action :mark_range_end_and_move

      # Stores data to context
      outputs [:start_message_id, :end_message_id]

      # What happens next
      on_complete :analyze_messages
    end

    step :analyze_messages do
      action :analyze_messages

      # Read from context
      inputs [:start_message_id, :end_message_id]

      # Write to context
      outputs [:messages_to_move]

      on_success :await_confirmation
      on_error :handle_analysis_error

      queue :message_processing
      max_attempts 3
    end

    step :await_confirmation do
      type :manual
      inputs [:messages_to_move]
      outputs [:destination_channel_id]

      # Multiple possible completions
      completion_actions do
        action :confirm_move, advances_to: :prepare_webhooks
        action :cancel_move, advances_to: :fail_workflow
      end
    end

    step :prepare_webhooks do
      action :prepare_webhooks
      inputs [:destination_channel_id]
      outputs [:webhook_id, :webhook_token]

      on_success :move_messages
      on_error :handle_webhook_error

      queue :message_processing
    end

    step :move_messages do
      action :move_messages
      inputs [:messages_to_move, :webhook_id, :webhook_token]

      on_success :cleanup
      queue :message_processing
    end

    # ... more steps
  end
end

# Generated:
# - Workflow context map with typed fields
# - Oban triggers for automatic steps
# - Manual action handlers for pausable steps
# - Input/output validation
# - Context persistence between steps
```

**Pros:**

- **Clear data flow** - inputs/outputs explicit
- Type-safe context
- Supports both automatic and manual steps
- Explicit control flow (on_success)
- Easy to understand dependencies

**Cons:**

- More verbose than Option 3
- Manual context schema definition
- Still some boilerplate

---

## Recommendation Matrix

| Option                     | Best For                           | Complexity | Boilerplate | Steward Fit |
| -------------------------- | ---------------------------------- | ---------- | ----------- | ----------- |
| **1. State-Based**         | Teams used to current pattern      | Medium     | High        | ⭐⭐⭐⭐⭐  |
| **2. Dependency-Based**    | Flexible workflows, parallel steps | High       | Low         | ⭐⭐⭐      |
| **3. Linear Pipeline**     | Simple sequential workflows        | Low        | Very Low    | ⭐⭐⭐⭐    |
| **4. State Machine First** | Complex state logic                | High       | High        | ⭐⭐⭐      |
| **5. Hybrid Control**      | Mixed automatic/manual workflows   | Medium     | Medium      | ⭐⭐⭐⭐⭐  |

## My Recommendation: **Option 5 (Hybrid Control)** with fallback to **Option 3 (Linear Pipeline)**

**Rationale:**

**Option 5** best fits Steward's requirements:

- ✅ Supports manual pause points naturally (`type: :manual`)
- ✅ Explicit control flow matches current mental model
- ✅ Type-safe context with inputs/outputs
- ✅ Handles both automatic and user-triggered steps
- ✅ Reduces boilerplate significantly vs current
- ✅ Clear data flow makes debugging easier

**Option 3** as simpler alternative if Option 5 is too complex:

- ✅ Minimal syntax
- ✅ Natural for sequential workflows
- ✅ Easy to learn
- ✅ Still supports pause points
- ❌ Less explicit about data flow

**Why not the others:**

- **Option 1**: Too close to current (not enough improvement)
- **Option 2**: Parallel execution concerns, less obvious flow
- **Option 4**: Too verbose, state machine terminology overkill

---

## Questions for User

1. **Parallelization**: Do you foresee needing parallel step execution in the
   future? Or are Steward's workflows always sequential?

2. **Context Schema**: Would you prefer explicit typed context fields (Option 5)
   or implicit map-based context (Option 3)?

3. **Control Flow Style**: Do you prefer explicit `on_success` / `on_error`
   routing, or dependency-based implicit ordering?

4. **Boilerplate vs Explicitness**: What's more important - minimal DSL code or
   explicit documentation of behavior?

5. **Migration Path**: Should the DSL be designed to make migrating existing
   Steward workflows easy?

---

## Next Steps

1. **User reviews options** and provides feedback
2. **Prototype chosen option** with MessageMove workflow
3. **Validate against all Steward patterns** (ImageGeneration too)
4. **Refine based on real-world feedback**
5. **Document migration guide** from current pattern
