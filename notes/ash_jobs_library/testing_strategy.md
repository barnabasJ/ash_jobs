# AshJobs Comprehensive TDD/BDD Testing Strategy

**Document Type:** Test Architecture & Strategy  
**Created:** 2025-10-24  
**Status:** Ready for Implementation  
**Target Audience:** Development team implementing AshJobs v0.1.0

---

## Executive Summary

This document provides a comprehensive TDD/BDD testing strategy for the AshJobs
library, covering:

- **4 Component Categories** with specific testing approaches
- **Test Organization Structure** aligned with project architecture
- **Testing Tools & Frameworks** beyond ExUnit
- **Behavior Specifications** for each component type
- **Quality Gates** at task, stream, and system levels
- **Acceptance Criteria Patterns** for production readiness

The strategy targets **95%+ test coverage** with emphasis on **critical paths**
and **edge cases**, while maintaining **test maintainability** and **execution
speed**.

---

## Table of Contents

1. [Testing Philosophy](#testing-philosophy)
2. [Component Types & Testing Approaches](#component-types--testing-approaches)
3. [Test Organization Structure](#test-organization-structure)
4. [Testing Tools & Frameworks](#testing-tools--frameworks)
5. [Unit Testing Patterns](#unit-testing-patterns)
6. [Integration Testing Patterns](#integration-testing-patterns)
7. [Property-Based Testing](#property-based-testing)
8. [Quality Gates & Acceptance Criteria](#quality-gates--acceptance-criteria)
9. [Performance Testing](#performance-testing)
10. [Error Scenario Testing](#error-scenario-testing)
11. [Test Data & Fixtures](#test-data--fixtures)
12. [Continuous Integration](#continuous-integration)

---

## Testing Philosophy

### Core Principles

**1. Test-Driven Development (TDD)**

Write tests **before** implementing functionality:

```
RED → GREEN → REFACTOR
 ↑      ↑        ↑
Test   Code    Improve
fails  passes  with tests
                 passing
```

- **RED Phase:** Write failing test that describes desired behavior
- **GREEN Phase:** Write minimum code to pass test
- **REFACTOR Phase:** Improve code while keeping tests passing

**2. Behavior-Driven Development (BDD)**

Use **acceptance criteria** to drive test design:

```
GIVEN [context/setup]
WHEN  [action occurs]
THEN  [expected outcome]
```

**3. Testing Pyramid**

```
     ▲
    ╱│╲   Few slow tests (End-to-End)
   ╱ │ ╲  - Real database
  ╱──┼──╲ - Full Oban integration
 ╱   │   ╲- Real compilation
╱────┼────╲
│ Integration Tests (30%)
├─────────────────────── - Mock external services
│Integration with Oban   - Use test database
├─────────────────────── - Compile full resources
│          │
├──────────┼──────────────
│   Unit Tests (60%)      - Fast, isolated
├──────────┼──────────────- Single component
│ DSL/Transformers       - No database required
│Verifiers/Info module   - No Oban integration
│Helper functions        │
├────────────────────────┴─
 Many fast tests
 Property-based (10%)
 Stream property checks
```

### Testing Mindset

**For Each Component, Ask:**

1. **What should happen?** (happy path)
2. **What shouldn't happen?** (failure modes)
3. **What edge cases exist?** (boundaries)
4. **How should it fail gracefully?** (error handling)
5. **Can it be composed/reused?** (integration points)

---

## Component Types & Testing Approaches

### 1. DSL Entities (sections, step entities)

**What they are:**

- `lib/ash_jobs/dsl/sections.ex` - Workflow section definition
- `lib/ash_jobs/dsl/entities/step.ex` - Step entity schema

**Testing Focus:** Schema validation, DSL parsing correctness

#### Spark DSL Entity Testing Pattern

```elixir
defmodule AshJobs.Dsl.Entities.StepTest do
  use ExUnit.Case

  describe "step entity schema" do
    test "step requires action attribute" do
      # Spark validates schema at compile time
      # Test by attempting resource compilation
      assert_raise CompileError, ~r/action is required/, fn ->
        Code.compile_quoted(quote do
          defmodule TestResource do
            use Ash.Resource, extensions: [AshJobs]

            workflow do
              step :missing_action do
                # Intentionally missing action
              end
            end
          end
        end)
      end
    end

    test "step on_success is required" do
      # Test validation requirement
    end

    test "step accepts optional timeout_seconds" do
      # Test optional attributes
    end

    test "step accepts optional queue" do
      # Test default values
    end

    test "step with trigger: false sets manual mode" do
      # Test feature flags
    end
  end
end
```

**Key Testing Areas:**

| Aspect              | Test Case                                | Pattern                  |
| ------------------- | ---------------------------------------- | ------------------------ |
| **Required Fields** | Missing action, on_success               | Expect compilation error |
| **Optional Fields** | timeout_seconds, queue                   | Defaults applied         |
| **Type Validation** | action must be atom, queue as string     | Type checking            |
| **Feature Flags**   | trigger: false enables manual mode       | Boolean handling         |
| **Step References** | on_success/on_error point to valid steps | Reference validation     |

**Testing Tools:**

- **ExUnit** - Standard test framework
- **Spark.Dsl.Transformer mocks** - Mock DSL operations
- **Code.compile_quoted/1** - Test compilation errors

---

### 2. Transformers (integrate_state_machine, integrate_oban, generate_error_actions)

**What they are:**

- `lib/ash_jobs/transformers/integrate_state_machine.ex` - Generate state
  machine DSL
- `lib/ash_jobs/transformers/integrate_oban.ex` - Generate Oban triggers
- `lib/ash_jobs/transformers/generate_error_actions.ex` - Generate error
  handlers

**Testing Focus:** Code generation correctness, DSL construction

#### Transformer Testing Pattern

```elixir
defmodule AshJobs.Transformers.IntegrateStateMachineTest do
  use ExUnit.Case

  describe "transformer correctness" do
    test "generates state_machine section with correct states" do
      # Setup: Create a test workflow DSL structure
      workflow_steps = [
        %{name: :step_one, on_success: :step_two},
        %{name: :step_two, on_success: :completed}
      ]

      # Act: Run transformer
      dsl_state = %Spark.Dsl.State{
        # ... mock DSL state
      }

      {:ok, transformed} = IntegrateStateMachine.transform(dsl_state)

      # Assert: Verify generated state_machine section
      state_machine = Spark.Dsl.Transformer.get_option(transformed, [:state_machine])
      assert state_machine.state_attribute == :state
      assert Enum.map(state_machine.states, & &1.name) ==
             [:step_one, :step_two, :completed, :failed, :cancelled]
    end

    test "generates transitions from on_success/on_error routing" do
      # Test transition generation
      # Assert: Verify transition logic
    end

    test "handles custom state_attribute option" do
      # Test configurable state attribute
    end

    test "skips generation if state_machine already defined" do
      # Test idempotency
    end
  end

  describe "error handling" do
    test "fails gracefully on invalid workflow structure" do
      # Test error scenarios
    end

    test "provides helpful error messages" do
      # Test user guidance
    end
  end
end
```

**Key Testing Areas:**

| Aspect                  | What to Test                                  | Approach                       |
| ----------------------- | --------------------------------------------- | ------------------------------ |
| **Correct Generation**  | States match steps, transitions match routing | Compare generated DSL entities |
| **Spark.Dsl functions** | Builder functions work correctly              | Mock/stub Spark functions      |
| **Idempotency**         | Don't generate if already exists              | Test "already exists" case     |
| **Edge Cases**          | Circular references, missing targets          | Test error detection           |
| **Integration**         | Generated entities integrate with Ash         | Compile partial resources      |

**Testing Tools:**

- **ExUnit** - Test execution
- **assert_dsl_equals/2** - Custom assertion for DSL comparison
- **Spark.Dsl.Transformer mocks** - Test transformer operations
- **Code compilation** - Validate generated code compiles

---

### 3. Verifiers (validate_workflow)

**What they are:**

- `lib/ash_jobs/verifiers/validate_workflow.ex` - Workflow validation after
  transformers

**Testing Focus:** Validation logic, error detection, helpful error messages

#### Verifier Testing Pattern

```elixir
defmodule AshJobs.Verifiers.ValidateWorkflowTest do
  use ExUnit.Case

  describe "workflow validation" do
    test "validates all step references are valid" do
      # Create workflow with invalid reference
      resource_with_invalid_ref = quote do
        defmodule TestResource do
          use Ash.Resource, extensions: [AshJobs]

          workflow do
            step :step_one do
              action :action_one
              on_success :nonexistent_step  # Invalid reference
            end
          end
        end
      end

      # Compilation should fail with helpful message
      assert_raise Ash.Error.DslError,
        ~r/step reference.*nonexistent_step.*not found/, fn ->
        Code.compile_quoted(resource_with_invalid_ref)
      end
    end

    test "detects circular dependencies in routing" do
      # Test circular reference detection
      # A -> B -> A should fail
    end

    test "ensures at least one entry point step" do
      # Every workflow needs starting step
    end

    test "validates user-defined actions exist" do
      # Each step.action must exist in resource.actions
    end

    test "validates state attribute type is :atom" do
      # State attribute must work with ash_state_machine
    end
  end

  describe "error messages" do
    test "provides clear message for invalid step reference" do
      # Error message quality is important
    end

    test "suggests fixes for common mistakes" do
      # Educational error messages
    end
  end
end
```

**Key Testing Areas:**

| Validation Type           | Test Cases                                | Expected Behavior      |
| ------------------------- | ----------------------------------------- | ---------------------- |
| **Step References**       | Valid/invalid on_success/on_error targets | Pass/fail with message |
| **Circular Dependencies** | A→B→A, A→B→C→A                            | Detected and reported  |
| **Entry Points**          | At least one step with no incoming edges  | Validated              |
| **Terminal States**       | Only :completed, :failed, :cancelled      | Validated              |
| **Action Existence**      | Each step.action in resource.actions      | Verified               |
| **Type Validation**       | State attribute is :atom                  | Checked                |

**Testing Tools:**

- **ExUnit** - Test framework
- **assert_raise/2** - Test error conditions
- **Graph algorithms** - Test cycle detection

---

### 4. Integration Tests

**What they are:**

- Full workflow compilation
- End-to-end execution
- Oban integration
- State machine coordination

**Testing Focus:** Everything works together correctly

#### Integration Testing Pattern

```elixir
defmodule AshJobs.Integration.WorkflowExecutionTest do
  use ExUnit.Case

  # Full resource definition
  defmodule TestWorkflow do
    use Ash.Resource, extensions: [AshJobs, AshStateMachine, AshOban]

    attributes do
      attribute :status, :atom, default: :initial
    end

    actions do
      update :step_one do
        change {Ash.Change, fn changeset, _ ->
          Ash.Changeset.change_attribute(changeset, :status, :step_one_done)
        end}
      end

      update :step_two do
        change {Ash.Change, fn changeset, _ ->
          Ash.Changeset.change_attribute(changeset, :status, :step_two_done)
        end}
      end
    end

    workflow do
      step :first_step do
        action :step_one
        on_success :second_step
      end

      step :second_step do
        action :step_two
        on_success :completed
      end
    end
  end

  test "workflow executes end-to-end successfully" do
    # Create initial record
    {:ok, record} = TestWorkflow.create!(%{})
    assert record.state == :first_step

    # Trigger first step
    {:ok, updated} = TestWorkflow.step_one(record)
    assert updated.state == :second_step
    assert updated.status == :step_one_done

    # Trigger second step
    {:ok, final} = TestWorkflow.step_two(updated)
    assert final.state == :completed
    assert final.status == :step_two_done
  end

  test "manual pause point waits for external trigger" do
    # Test trigger: false behavior
  end

  test "error routing works correctly" do
    # Test on_error behavior
  end

  test "state transitions are atomic" do
    # Test database consistency
  end
end
```

---

## Test Organization Structure

```
test/
├── ash_jobs/
│   ├── dsl/
│   │   ├── sections_test.exs           # Workflow section definition
│   │   └── entities/
│   │       └── step_test.exs           # Step entity schema
│   │
│   ├── transformers/
│   │   ├── integrate_state_machine_test.exs
│   │   ├── integrate_oban_test.exs
│   │   ├── generate_error_actions_test.exs
│   │   └── build_workflow_test.exs     # (if created)
│   │
│   ├── verifiers/
│   │   └── validate_workflow_test.exs
│   │
│   ├── info_test.exs                   # Info/introspection module
│   ├── change_test.exs                 # Global Change module routing
│   └── helpers_test.exs                # Helper functions
│
├── integration/
│   ├── workflow_execution_test.exs     # End-to-end workflows
│   ├── state_machine_integration_test.exs
│   ├── oban_integration_test.exs
│   ├── error_handling_test.exs
│   ├── manual_steps_test.exs           # trigger: false behavior
│   └── complex_workflows_test.exs      # Multi-step scenarios
│
├── property_based/
│   ├── workflow_generation_test.exs    # StreamData workflows
│   └── routing_correctness_test.exs    # Property tests for routing
│
└── support/
    ├── test_resource.ex                # Reusable test resource
    ├── test_helpers.ex                 # Shared test utilities
    ├── fixtures.ex                     # Test data generators
    └── assertions.ex                   # Custom assertions
```

---

## Testing Tools & Frameworks

### Required Testing Tools

#### 1. **ExUnit** (Built-in)

- Standard Elixir test framework
- All basic unit tests run here
- Usage: `mix test`

#### 2. **Mimic** (~> 1.11)

```elixir
# In mix.exs
{:mimic, "~> 1.11", only: :test}

# Usage: Mock Spark.Dsl.Transformer functions
# In test_helper.exs
Mimic.copy(Spark.Dsl.Transformer)

# In test
Mimic.stub(Spark.Dsl.Transformer, :get_option, fn _state, _path -> {:ok, nil} end)
```

#### 3. **StreamData** (~> 1.1) - Property-Based Testing

```elixir
# In mix.exs
{:stream_data, "~> 1.1", only: :test}

# Usage: Generate random workflows
property "all workflow steps are reachable" do
  check all(workflow <- workflow_generator()) do
    reachable = compute_reachable_steps(workflow)
    all_steps = MapSet.new(Enum.map(workflow.steps, & &1.name))

    assert MapSet.equal?(reachable, all_steps)
  end
end
```

#### 4. **Oban.Testing** (Built-in)

```elixir
# Test mode configuration
config :my_app, Oban, testing: :manual

# Or inline execution
Oban.Testing.with_testing_mode(:inline) do
  # Triggers fire synchronously
end

# Manual job execution
Oban.Testing.perform_job(TestWorkflow.AvailableAction, job)
```

#### 5. **Ash Testing Utilities**

```elixir
# Use Ash's built-in test helpers
import Ash.Test.Helpers

# Compile resources for testing
require_ash_types!()

# Create test resources
defmodule TestResource do
  use Ash.Resource
  # ...
end
```

### Optional Advanced Testing Tools

#### **ExVCR** (~> 0.15) - HTTP Recording

```elixir
# For testing external API calls within actions
{:exvcr, "~> 0.15", only: :test}
```

#### **Benchee** (~> 1.1) - Performance Testing

```elixir
# For performance testing transformers
{:benchee, "~> 1.1", only: :test}
```

---

## Unit Testing Patterns

### Pattern 1: DSL Entity Tests

```elixir
defmodule AshJobs.Dsl.Entities.StepTest do
  use ExUnit.Case, async: true

  describe "step entity validation" do
    test "accepts all valid options" do
      valid_step = %Spark.Dsl.Entity{
        name: :test_step,
        target: AshJobs.Dsl.Entities.Step,
        args: [:test_step],
        schema: [
          action: :test_action,
          on_success: :next_step,
          queue: :default,
          timeout_seconds: 30,
          retry_attempts: 3,
          trigger: true
        ]
      }

      assert valid_step.args == [:test_step]
      assert valid_step.schema[:action] == :test_action
    end

    test "validates on_success is present" do
      # Spark validates at compilation
      # This test documents the requirement
    end
  end
end
```

### Pattern 2: Transformer Tests

```elixir
defmodule AshJobs.Transformers.IntegrateStateMachineTest do
  use ExUnit.Case, async: true

  setup :verify_on_exit!

  setup do
    # Minimal mock DSL state
    {:ok, %{
      workflow: %{
        steps: [
          %{name: :step_one, on_success: :step_two},
          %{name: :step_two, on_success: :completed}
        ]
      },
      dsl_state: %Spark.Dsl.State{
        module: Test.Module,
        # ...
      }
    }}
  end

  test "generates state_machine with correct structure", %{dsl_state: state} do
    {:ok, transformed} = AshJobs.Transformers.IntegrateStateMachine.transform(state)

    # Extract generated state_machine
    # Verify states and transitions
    assert has_state?(transformed, :step_one)
    assert has_state?(transformed, :step_two)
    assert has_state?(transformed, :completed)
  end

  defp has_state?(dsl_state, state_name) do
    # Helper to check if state exists
    case Spark.Dsl.Transformer.get_option(dsl_state, [:state_machine, :states]) do
      {:ok, states} -> Enum.any?(states, & &1.name == state_name)
      :error -> false
    end
  end
end
```

### Pattern 3: Verifier Tests

```elixir
defmodule AshJobs.Verifiers.ValidateWorkflowTest do
  use ExUnit.Case, async: true

  test "detects circular dependencies" do
    # Create workflow with cycle
    workflow = %{
      steps: [
        %{name: :a, on_success: :b},
        %{name: :b, on_success: :a}  # Cycle!
      ]
    }

    # Run verifier
    result = AshJobs.Verifiers.ValidateWorkflow.verify_workflow(workflow)

    # Assert error
    assert {:error, %Ash.Error.DslError{message: msg}} = result
    assert msg =~ "circular"
  end

  test "validates all on_success targets exist" do
    workflow = %{
      steps: [
        %{name: :step_one, on_success: :nonexistent}
      ]
    }

    result = AshJobs.Verifiers.ValidateWorkflow.verify_workflow(workflow)

    assert {:error, %Ash.Error.DslError{}} = result
  end
end
```

---

## Integration Testing Patterns

### Pattern 1: Full Workflow Execution

```elixir
defmodule AshJobs.Integration.WorkflowExecutionTest do
  use ExUnit.Case

  setup do
    # Define full test resource
    {:ok, %{
      resource: create_test_resource()
    }}
  end

  test "complete workflow executes successfully" do
    # 1. Create initial record
    {:ok, job} = Ash.create!(TestWorkflow, %{})
    assert job.state == :step_one

    # 2. Execute step one
    {:ok, job} = Ash.update!(job, :step_one_action)
    assert job.state == :step_two

    # 3. Execute step two
    {:ok, job} = Ash.update!(job, :step_two_action)
    assert job.state == :completed
  end

  test "workflow handles errors correctly" do
    {:ok, job} = Ash.create!(TestWorkflow, %{})

    # Simulate error in step
    assert_raise RuntimeError, fn ->
      Ash.update!(job, :failing_action)
    end

    # Verify error state
    {:ok, reloaded} = Ash.read_one(TestWorkflow)
    assert reloaded.state == :error_handler
  end

  test "state transitions are persisted" do
    # Create job
    {:ok, job} = Ash.create!(TestWorkflow, %{})
    initial_id = job.id

    # Update through steps
    Ash.update!(job, :step_one_action)

    # Reload and verify
    {:ok, reloaded} = Ash.read(TestWorkflow, initial_id)
    assert reloaded.state != :step_one
  end
end
```

### Pattern 2: Oban Integration Tests

```elixir
defmodule AshJobs.Integration.ObanIntegrationTest do
  use ExUnit.Case

  test "triggers are created for workflow steps" do
    # Verify trigger generation
    triggers = Ash.Resource.Info.triggers(TestWorkflow)

    assert Enum.any?(triggers, & &1.name == :step_one)
    assert Enum.any?(triggers, & &1.name == :step_two)
  end

  test "triggers fire in sequence" do
    Oban.Testing.with_testing_mode(:inline) do
      # Create job
      {:ok, job} = Ash.create!(TestWorkflow, %{})

      # Oban trigger fires automatically
      # Workflow progresses

      {:ok, reloaded} = Ash.read_one(TestWorkflow, job.id)
      assert reloaded.state == :step_two  # Progressed
    end
  end

  test "manual pause steps don't trigger automatically" do
    # Manual pause step with trigger: false
    # Verify no automatic trigger
  end
end
```

---

## Property-Based Testing

### Pattern 1: Workflow Generation

```elixir
defmodule AshJobs.PropertyBasedTest.WorkflowGenerationTest do
  use ExUnit.Case

  import StreamData

  property "all steps reachable from entry point" do
    check all(workflow <- workflow_generator()) do
      # Compute reachable steps
      entry_point = workflow.entry_step
      reachable = compute_reachable(workflow, entry_point)
      all_steps = MapSet.new(Enum.map(workflow.steps, & &1.name))

      # All steps must be reachable
      assert MapSet.equal?(reachable, all_steps)
    end
  end

  property "no circular dependencies" do
    check all(workflow <- workflow_generator()) do
      refute has_cycle?(workflow)
    end
  end

  # Workflow generator
  defp workflow_generator do
    gen all(
      step_count <- integer(1..10),
      steps <- list_of(step_generator(), length: step_count)
    ) do
      # Build valid workflow structure
      build_workflow(steps)
    end
  end

  defp step_generator do
    gen all(
      name <- atom(:alias),
      action <- atom(:alias)
    ) do
      %{name: name, action: action}
    end
  end
end
```

---

## Quality Gates & Acceptance Criteria

### Level 1: Task-Level Quality Gates

**For each feature/task:**

```elixir
# Every test file must include:

describe "unit tests" do
  test "behavior described by acceptance criteria" do
    # Given-When-Then format
    given_setup()

    when_action_occurs()

    then_assert_expected_outcome()
  end

  test "error scenarios" do
    given_error_condition()

    when_action_attempted()

    then_assert_graceful_failure()
  end

  test "edge cases" do
    given_boundary_condition()

    when_action_occurs()

    then_assert_correct_behavior()
  end
end
```

**Acceptance Criteria for Components:**

| Component         | Acceptance Criteria                                             |
| ----------------- | --------------------------------------------------------------- |
| **Step Entity**   | Schema defined, all options documented, validation works        |
| **Transformer**   | Generates correct DSL entities, handles errors, skips if exists |
| **Verifier**      | Detects all error conditions, provides helpful messages         |
| **Change Module** | Routes correctly, transitions state, schedules next job         |

### Level 2: Stream-Level Quality Gates

**For integration tests (workflow execution streams):**

```
SUCCESS PATH
  ✓ Happy path completes without errors
  ✓ State transitions occur in correct order
  ✓ Data persists between steps
  ✓ Final state is terminal (:completed)

ERROR PATH
  ✓ Errors transition to error handler
  ✓ Error state is correct (:failed)
  ✓ Error details are logged

MANUAL PAUSE POINT
  ✓ Automatic steps fire normally
  ✓ Manual steps don't fire automatically
  ✓ Manual steps can be triggered externally
  ✓ Manual advance respects routing

RETRY LOGIC
  ✓ Failed steps retry configured times
  ✓ Retry delay is applied
  ✓ Max retries transitions to error handler

EDGE CASES
  ✓ Single-step workflows work
  ✓ Workflows with many steps work
  ✓ Complex error paths work
  ✓ Concurrent workflows don't interfere
```

### Level 3: System-Level Quality Gates

**Overall library readiness:**

| Gate              | Success Criteria                | Validation Method          |
| ----------------- | ------------------------------- | -------------------------- |
| **Code Coverage** | 95%+ lines, 85%+ branches       | `mix test --cover`         |
| **Type Safety**   | 0 Dialyzer warnings             | `mix dialyzer`             |
| **Code Quality**  | 0 Credo issues (strict)         | `mix credo --strict`       |
| **Formatting**    | 100% formatted correctly        | `mix format --check`       |
| **Compilation**   | 0 warnings in all modes         | `MIX_ENV=test mix compile` |
| **Documentation** | All public functions documented | `ex_doc` generated docs    |
| **Performance**   | <10ms overhead, <5ms per step   | Load testing results       |

---

## Performance Testing

### Scenario 1: Transformer Performance

```elixir
defmodule AshJobs.Performance.TransformerTest do
  use ExUnit.Case

  @tag :performance
  test "transformer completes quickly for large workflows" do
    # Create workflow with 50 steps
    steps = Enum.map(1..50, fn i ->
      %{name: :"step_#{i}", action: :"action_#{i}", on_success: :"step_#{i+1}"}
    end)

    workflow = %{steps: steps}

    # Measure transformer execution
    {microseconds, _result} = :timer.tc(fn ->
      AshJobs.Transformers.IntegrateStateMachine.transform(workflow)
    end)

    milliseconds = microseconds / 1000

    # Assert <10ms for 50 steps
    assert milliseconds < 10,
      "Transformer took #{milliseconds}ms for 50 steps"
  end
end
```

### Scenario 2: Workflow Execution Performance

```elixir
defmodule AshJobs.Performance.ExecutionTest do
  use ExUnit.Case

  @tag :performance
  test "1000 workflows/minute throughput" do
    workflow_count = 16  # 16 per second = 1000/min

    {microseconds, _} = :timer.tc(fn ->
      Enum.each(1..workflow_count, fn _ ->
        Ash.create!(TestWorkflow, %{})
      end)
    end)

    milliseconds = microseconds / 1000
    per_workflow = milliseconds / workflow_count

    assert per_workflow < 10,
      "Average workflow creation: #{per_workflow}ms (target: <10ms)"
  end
end
```

---

## Error Scenario Testing

### Scenario 1: DSL Compilation Errors

```elixir
defmodule AshJobs.ErrorScenarios.DslCompilationTest do
  use ExUnit.Case

  test "meaningful error for missing action" do
    error = assert_raise Ash.Error.DslError, fn ->
      Code.compile_quoted(quote do
        defmodule BadWorkflow do
          use Ash.Resource, extensions: [AshJobs]

          workflow do
            step :my_step do
              action :nonexistent_action
              on_success :completed
            end
          end
        end
      end)
    end

    assert error.message =~ "action"
    assert error.message =~ "not found"
    assert error.message =~ "define the action"  # Helpful suggestion
  end

  test "meaningful error for circular dependency" do
    error = assert_raise Ash.Error.DslError, fn ->
      # Create circular workflow
    end

    assert error.message =~ "circular"
    assert error.message =~ "dependency"
  end
end
```

### Scenario 2: Runtime Errors

```elixir
defmodule AshJobs.ErrorScenarios.RuntimeTest do
  use ExUnit.Case

  test "workflow recovers from action failure" do
    {:ok, job} = Ash.create!(TestWorkflow, %{})

    # Mock action failure
    assert_raise RuntimeError, fn ->
      Ash.update!(job, :failing_action)
    end

    # Verify error state
    {:ok, reloaded} = Ash.read_one(TestWorkflow)
    assert reloaded.state == :error_handler
    assert reloaded.last_error =~ "RuntimeError"
  end

  test "timeout is handled gracefully" do
    # Simulate timeout scenario
    # Verify transition to failed state
  end
end
```

---

## Test Data & Fixtures

### Fixture Pattern 1: Test Resource Factory

```elixir
# test/support/test_resource.ex

defmodule AshJobs.Test.Support.TestResource do
  @moduledoc """
  Reusable test resource with workflow for integration tests.
  """

  use Ash.Resource, extensions: [AshJobs, AshStateMachine, AshOban]

  attributes do
    attribute :name, :string
    attribute :status, :atom, default: :pending
    attribute :error_log, :string
  end

  actions do
    create :create
    update :step_one_action
    update :step_two_action
    update :step_three_action
  end

  workflow do
    step :step_one do
      action :step_one_action
      on_success :step_two
      on_error :error_handler
    end

    step :step_two do
      action :step_two_action
      on_success :step_three
      on_error :error_handler
    end

    step :step_three do
      action :step_three_action
      on_success :completed
    end

    step :error_handler do
      action :record_error
      on_complete :failed
    end
  end
end
```

### Fixture Pattern 2: Test Helpers

```elixir
# test/support/test_helpers.ex

defmodule AshJobs.Test.Support.Helpers do
  @doc "Create and return initial workflow job"
  def create_test_job(attrs \\ %{}) do
    attrs = Map.merge(%{name: "Test"}, attrs)
    Ash.create!(TestWorkflow, attrs)
  end

  @doc "Execute workflow through N steps"
  def run_workflow_steps(job, step_count) do
    Enum.reduce(1..step_count, job, fn step, current_job ->
      action = :"step_#{step}_action"
      {:ok, updated} = Ash.update!(current_job, action)
      updated
    end)
  end

  @doc "Assert workflow state equals expected"
  def assert_workflow_state(job, expected_state) do
    assert job.state == expected_state
  end

  @doc "Get compiled test resource"
  def get_test_workflow do
    # Return precompiled test resource
  end
end
```

---

## Continuous Integration

### CI Pipeline Configuration

```yaml
# .github/workflows/test.yml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready --health-interval 10s --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3

      - uses: erlef/setup-elixir@v1
        with:
          elixir-version: 1.18
          otp-version: 27

      - name: Install dependencies
        run: mix deps.get

      - name: Check formatting
        run: mix format --check-formatted

      - name: Run Credo
        run: mix credo --strict

      - name: Run tests
        run: mix test
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost/ash_jobs_test

      - name: Check test coverage
        run: mix test --cover

      - name: Run Dialyzer
        run: mix dialyzer --no-check

      - name: Build docs
        run: mix docs
```

### Local Development Commands

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run integration tests only
mix test test/integration

# Run specific test file
mix test test/ash_jobs/transformers/integrate_state_machine_test.exs

# Run with verbose output
mix test --trace

# Run property-based tests
mix test test/property_based

# Check code quality
mix format --check-formatted
mix credo --strict
mix dialyzer

# Build documentation
mix docs
```

---

## Behavior Specifications by Component

### DSL Entities Behavior Spec

```
GIVEN a step entity definition
WHEN compiled as part of a workflow
THEN the following behaviors are verified:

1. Schema Validation
   ✓ action attribute is required
   ✓ on_success attribute is required
   ✓ queue defaults to :default
   ✓ timeout_seconds defaults to no timeout
   ✓ retry_attempts defaults to 1
   ✓ trigger defaults to true (automatic)

2. Type Safety
   ✓ action must be atom
   ✓ on_success must be atom
   ✓ queue must be atom
   ✓ timeout_seconds must be positive integer
   ✓ retry_attempts must be positive integer
   ✓ trigger must be boolean

3. Cross-Field Validation
   ✓ on_success must reference valid step or terminal state
   ✓ on_error must reference valid step or terminal state
   ✓ manual pause points (trigger: false) can be advanced manually

4. DSL Integration
   ✓ Multiple steps in single workflow
   ✓ Steps compose into valid workflow
   ✓ Step options merge with defaults correctly
```

### Transformer Behavior Spec

```
GIVEN a workflow definition with N steps
WHEN IntegrateStateMachine transformer runs
THEN the following are verified:

1. State Generation
   ✓ One state per step
   ✓ Three terminal states: :completed, :failed, :cancelled
   ✓ Custom state_attribute option is respected
   ✓ Defaults to :state attribute

2. Transition Generation
   ✓ One transition per on_success routing
   ✓ One transition per on_error routing
   ✓ Terminal transitions to :completed, :failed
   ✓ Transition names follow convention: :to_target_state

3. Initial State
   ✓ Entry point step is initial_state
   ✓ Unique entry point detected
   ✓ Entry point has no incoming edges

4. Error Handling
   ✓ Circular dependencies detected
   ✓ Invalid references detected
   ✓ Helpful error messages provided
   ✓ Error messages suggest fixes

5. Idempotency
   ✓ Transformer idempotent (can run twice safely)
   ✓ Skips generation if already exists
   ✓ Validates existing matches expected
```

### Verifier Behavior Spec

```
GIVEN a compiled workflow with state machine and Oban triggers
WHEN ValidateWorkflow verifier runs
THEN the following are verified:

1. Reference Validation
   ✓ All step references are valid
   ✓ on_success targets exist
   ✓ on_error targets exist
   ✓ Circular references detected

2. Completeness
   ✓ All steps have valid transitions
   ✓ All steps are reachable from entry
   ✓ No unreachable steps
   ✓ Terminal states are reachable

3. Action Validation
   ✓ Each step's action exists in resource
   ✓ Action signatures are compatible
   ✓ All required actions present

4. Type Safety
   ✓ State attribute is :atom type
   ✓ Workflow attributes have correct types
   ✓ Generated entities have correct types

5. DSL Consistency
   ✓ Generated state_machine matches workflow
   ✓ Generated triggers match workflow
   ✓ state_attribute used consistently
```

---

## Summary: Implementation Checklist

### Before Writing Any Feature Code

- [ ] Write acceptance criteria in BDD format
- [ ] Create failing test that documents criteria
- [ ] Verify test fails (RED phase)

### During Feature Implementation

- [ ] Implement minimum code to pass test (GREEN phase)
- [ ] Verify all tests pass
- [ ] Refactor while keeping tests passing (REFACTOR phase)
- [ ] Add tests for edge cases
- [ ] Add tests for error scenarios

### Before Task Completion

- [ ] Unit tests: 100% passing
- [ ] Integration tests: 100% passing
- [ ] Property-based tests: 100% passing
- [ ] Code coverage: 95%+ achieved
- [ ] No Dialyzer warnings
- [ ] Code formatted correctly
- [ ] Credo passes (strict mode)
- [ ] Documentation updated

### Before Component Merge

- [ ] All quality gates passing
- [ ] Code review completed
- [ ] Integration with other components verified
- [ ] Performance benchmarks acceptable
- [ ] No regressions in existing tests

---

## Next Steps

1. **Implement DSL Entities Tests** - Start with step entity schema tests
2. **Implement Transformer Tests** - Test each transformer independently
3. **Implement Verifier Tests** - Test validation logic
4. **Build Integration Tests** - Test end-to-end workflows
5. **Add Property-Based Tests** - Generate random workflows
6. **Set Up CI Pipeline** - Automate quality checks

---

**Document Status:** Ready for Implementation  
**Test Framework:** ExUnit + Mimic + StreamData + Oban.Testing  
**Coverage Target:** 95%+ lines, 85%+ branches  
**Performance Target:** <10ms transformer overhead, 1000 workflows/min
throughput
