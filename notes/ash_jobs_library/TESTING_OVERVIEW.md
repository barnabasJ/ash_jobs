# AshJobs Testing Strategy - Complete Overview

**Document Type:** Testing Architecture Summary & Implementation Guide  
**Created:** 2025-10-24  
**Status:** Ready for Breakdown Phase & Implementation  
**Audience:** Development team implementing AshJobs v0.1.0

---

## What's in This Testing Package

This testing strategy provides comprehensive guidance for implementing TDD/BDD
for the AshJobs library. It includes:

### Core Documents

1. **testing_strategy.md** (36KB)

   - Comprehensive TDD/BDD testing strategy
   - 4 component types with specific testing approaches
   - Test organization structure for entire project
   - Testing tools & frameworks (ExUnit, Mimic, StreamData, Oban.Testing)
   - Unit, integration, and property-based testing patterns
   - Quality gates at task, stream, and system levels
   - Performance testing scenarios
   - Error scenario testing patterns
   - Test data & fixture patterns
   - CI/CD pipeline configuration

2. **ash_specific_testing_guidance.md** (22KB)
   - Elixir/Ash framework specific best practices
   - Spark DSL testing fundamentals
   - Transformer testing patterns
   - Ash resource compilation testing
   - ash_state_machine integration testing
   - ash_oban integration testing
   - Debugging common test failures
   - What NOT to test (Ash already does it)
   - Ash ecosystem testing best practices

---

## Quick Start: Test Implementation Order

### Phase 1: Unit Tests (Week 1-2)

**Focus:** Component isolation, fast execution

```
test/ash_jobs/
├── dsl/
│   ├── sections_test.exs           # ← Start here
│   └── entities/step_test.exs       # ← Then here
├── transformers/
│   ├── integrate_state_machine_test.exs
│   ├── integrate_oban_test.exs
│   └── generate_error_actions_test.exs
├── verifiers/
│   └── validate_workflow_test.exs
├── info_test.exs
├── change_test.exs
└── helpers_test.exs
```

**Success Criteria:**

- All unit tests passing
- 60%+ code coverage from unit tests alone
- Tests run in <5 seconds total

### Phase 2: Integration Tests (Week 3-4)

**Focus:** Cross-component interaction, end-to-end workflows

```
test/integration/
├── workflow_execution_test.exs      # ← Start here
├── state_machine_integration_test.exs
├── oban_integration_test.exs
├── error_handling_test.exs
├── manual_steps_test.exs
└── complex_workflows_test.exs
```

**Success Criteria:**

- All integration tests passing
- Coverage reaches 95%+
- Tests run in <30 seconds total

### Phase 3: Property-Based Tests (Week 4-5)

**Focus:** Invariant verification, edge case discovery

```
test/property_based/
├── workflow_generation_test.exs     # ← Start here
└── routing_correctness_test.exs
```

**Success Criteria:**

- 100+ property-based examples verified
- No uncaught edge cases
- ~10% of total test time

---

## Component-Specific Testing Approaches

### 1. DSL Entities (step entity, workflow section)

**What to Test:**

- Schema validation (required vs optional fields)
- Type checking
- Default values
- Feature flags (trigger: true/false)

**How to Test:**

```elixir
# Test by attempting resource compilation
assert_raise Ash.Error.DslError, ~r/action is required/, fn ->
  compile_resource("""
  workflow do
    step :my_step do
      # Missing action
      on_success :completed
    end
  end
  """)
end
```

**Files:**

- `test/ash_jobs/dsl/sections_test.exs`
- `test/ash_jobs/dsl/entities/step_test.exs`

### 2. Transformers (integrate_state_machine, integrate_oban, generate_error_actions)

**What to Test:**

- Correct DSL generation
- State machine states and transitions
- Oban trigger creation
- Error action generation
- Idempotency (don't generate if exists)
- Error handling and messages

**How to Test:**

```elixir
# Test by running transformer and verifying output
{:ok, transformed} = IntegrateStateMachine.transform(dsl_state)
states = get_state_machine_states(transformed)
assert Enum.any?(states, & &1.name == :step_one)
```

**Files:**

- `test/ash_jobs/transformers/integrate_state_machine_test.exs`
- `test/ash_jobs/transformers/integrate_oban_test.exs`
- `test/ash_jobs/transformers/generate_error_actions_test.exs`

### 3. Verifiers (validate_workflow)

**What to Test:**

- Circular dependency detection
- Invalid step reference detection
- Entry point validation
- Terminal state validation
- Action existence checks
- Helpful error messages

**How to Test:**

```elixir
# Test by attempting compilation with invalid config
assert_raise Ash.Error.DslError, ~r/circular/, fn ->
  compile_resource("""
  workflow do
    step :a do
      action :a_action
      on_success :b
    end
    step :b do
      action :b_action
      on_success :a  # Circular!
    end
  end
  """)
end
```

**Files:**

- `test/ash_jobs/verifiers/validate_workflow_test.exs`

### 4. Integration Tests (full workflows)

**What to Test:**

- Complete workflow execution
- State transitions in sequence
- Data persistence between steps
- Error routing and handling
- Manual pause points (trigger: false)
- Retry logic

**How to Test:**

```elixir
# Test by creating full resource and running it
{:ok, job} = Ash.create!(TestWorkflow, %{})
assert job.state == :step_one

{:ok, updated} = Ash.update!(job, :step_one_action)
assert updated.state == :step_two
```

**Files:**

- `test/integration/workflow_execution_test.exs`
- `test/integration/state_machine_integration_test.exs`
- `test/integration/oban_integration_test.exs`
- `test/integration/error_handling_test.exs`
- `test/integration/manual_steps_test.exs`
- `test/integration/complex_workflows_test.exs`

---

## Testing Tools & Setup

### Required Dependencies

Add to `mix.exs`:

```elixir
defp deps do
  [
    # ... existing deps
    {:mimic, "~> 1.11", only: :test},        # Mocking
    {:stream_data, "~> 1.1", only: :test},   # Property-based testing
  ]
end
```

### Test Configuration

In `config/test.exs`:

```elixir
import Config

# Oban testing configuration
config :ash_jobs, Oban,
  testing: :manual  # Don't auto-start jobs in tests

# Or use inline mode for workflow tests
# Oban.Testing.with_testing_mode(:inline) do
#   # Tests here run jobs synchronously
# end
```

### Test Helper Setup

Create `test/support/`:

```
test/support/
├── test_resource.ex          # Reusable test workflow resource
├── test_helpers.ex           # Common test utilities
├── fixtures.ex               # Test data generators
└── assertions.ex             # Custom assertions
```

---

## Quality Gates & Acceptance Criteria

### Task-Level Gates (Per Feature)

Each feature/task must pass:

```
✓ Unit tests written before implementation
✓ All acceptance criteria documented as tests
✓ Error scenarios tested
✓ Edge cases identified and tested
✓ Code coverage >95% for that component
✓ No Dialyzer warnings
✓ Code formatted with `mix format`
✓ Credo passes: `mix credo --strict`
```

### Stream-Level Gates (Component Integration)

For workflow execution streams:

```
SUCCESS PATH
  ✓ Happy path completes without errors
  ✓ State transitions in correct order
  ✓ Data persists between steps
  ✓ Final state is terminal

ERROR PATH
  ✓ Errors transition to error handler
  ✓ Error state is :failed
  ✓ Error details logged

MANUAL PAUSE
  ✓ Manual steps don't auto-fire
  ✓ Manual advance works
  ✓ Routing respected

RETRY LOGIC
  ✓ Failed steps retry N times
  ✓ Retry delay applied
  ✓ Max retries → error handler

EDGE CASES
  ✓ Single-step workflows
  ✓ Workflows with 10+ steps
  ✓ Concurrent workflows
  ✓ Complex error paths
```

### System-Level Gates (Overall Library)

For v0.1.0 release:

| Gate              | Criteria                        | Validation                 |
| ----------------- | ------------------------------- | -------------------------- |
| **Code Coverage** | 95%+ lines, 85%+ branches       | `mix test --cover`         |
| **Type Safety**   | 0 Dialyzer warnings             | `mix dialyzer`             |
| **Code Quality**  | 0 Credo issues (strict)         | `mix credo --strict`       |
| **Formatting**    | 100% formatted                  | `mix format --check`       |
| **Compilation**   | 0 warnings                      | `MIX_ENV=test mix compile` |
| **Documentation** | All public functions documented | `mix docs`                 |
| **Performance**   | <10ms transformer overhead      | Load tests                 |
| **Throughput**    | 1000 workflows/minute           | Performance tests          |

---

## Testing Strategy by Component Type

### DSL Entities Strategy

```
APPROACH: Compile-time schema validation
TOOLS: ExUnit, Code.compile_quoted
ASYNC: Yes (no database, no shared state)

TESTS:
1. Required fields enforced
2. Optional fields with defaults
3. Type checking
4. Cross-field validation
5. DSL integration

EXAMPLE:
test "step requires action" do
  assert_raise Ash.Error.DslError, ~r/action.*required/, fn ->
    compile_resource(~S"""
    workflow do
      step :s do
        on_success :next
      end
    end
    """)
  end
end
```

### Transformer Strategy

```
APPROACH: Code generation verification
TOOLS: ExUnit, Spark.Dsl.Transformer mocks
ASYNC: Yes (no database, isolated transformation)

TESTS:
1. Correct DSL entities generated
2. Correct values in generated entities
3. Handles pre-existing declarations
4. Error detection
5. Helpful error messages

EXAMPLE:
test "generates state_machine" do
  {:ok, transformed} = IntegrateStateMachine.transform(dsl_state)
  states = get_states(transformed)
  assert Enum.any?(states, & &1.name == :step_one)
end
```

### Verifier Strategy

```
APPROACH: Validation rule verification
TOOLS: ExUnit, Ash.Error.DslError testing
ASYNC: Yes (no database, isolated validation)

TESTS:
1. Circular dependency detection
2. Invalid references detection
3. All validation rules
4. Error messages (quality matters!)
5. Helpful suggestions

EXAMPLE:
test "detects circular dependency" do
  assert_raise Ash.Error.DslError, ~r/circular/, fn ->
    compile_resource(~S"""
    workflow do
      step :a do
        action :a_action
        on_success :b
      end
      step :b do
        action :b_action
        on_success :a
      end
    end
    """)
  end
end
```

### Integration Strategy

```
APPROACH: Full workflow execution
TOOLS: ExUnit, Oban.Testing
ASYNC: No (database operations must be serialized)

TESTS:
1. Complete workflows execute
2. State transitions work
3. Data persists
4. Error routing works
5. Manual pause points work
6. Retry logic works

EXAMPLE:
test "workflow executes end-to-end" do
  {:ok, job} = Ash.create!(TestWorkflow, %{})
  assert job.state == :step_one

  {:ok, updated} = Ash.update!(job, :step_one_action)
  assert updated.state == :step_two
end
```

### Property-Based Strategy

```
APPROACH: Invariant verification over random inputs
TOOLS: StreamData
ASYNC: Yes (no shared state)

TESTS:
1. All steps reachable from entry point
2. No circular dependencies possible
3. All transitions valid
4. Workflow always terminates

EXAMPLE:
property "all steps reachable" do
  check all(workflow <- workflow_generator()) do
    reachable = compute_reachable(workflow)
    all_steps = MapSet.new(Enum.map(workflow.steps, & &1.name))
    assert MapSet.equal?(reachable, all_steps)
  end
end
```

---

## Common Testing Patterns

### Pattern 1: Testing DSL Errors

```elixir
test "meaningful error when action missing" do
  error = assert_raise Ash.Error.DslError, fn ->
    compile_resource("""
    workflow do
      step :my_step do
        on_success :next
      end
    end
    """)
  end

  # Verify error quality
  assert error.message =~ "action"
  assert error.message =~ "required"
  assert error.message =~ "my_step"
end
```

### Pattern 2: Testing Code Generation

```elixir
test "generates correct state machine" do
  {:ok, transformed} = IntegrateStateMachine.transform(dsl_state)

  # Extract generated section
  {:ok, section} = Spark.Dsl.Transformer.get_section(transformed, [:state_machine])

  # Verify contents
  states = Spark.Dsl.Transformer.get_entities(section, [:states])
  assert Enum.any?(states, & &1.name == :my_step)
end
```

### Pattern 3: Testing Workflow Execution

```elixir
test "workflow transitions states correctly" do
  {:ok, job} = Ash.create!(TestWorkflow, %{})
  assert job.state == :step_one

  {:ok, updated} = Ash.update!(job, :step_one_action)
  assert updated.state == :step_two
end
```

### Pattern 4: Testing with Oban

```elixir
test "oban triggers fire in sequence" do
  Oban.Testing.with_testing_mode(:inline) do
    {:ok, job} = Ash.create!(TestWorkflow, %{})

    # Triggers fire synchronously
    {:ok, updated} = Ash.read_one(TestWorkflow, job.id)
    assert updated.state != :step_one  # Advanced!
  end
end
```

---

## Performance Expectations

### Build Performance

- **Transformer execution:** <10ms for 50-step workflow
- **Verifier execution:** <5ms for 50-step workflow
- **Workflow creation:** <10ms per workflow
- **State transition:** <5ms per transition

### Load Testing Target

- **1000 workflows/minute** (16 per second)
- Average workflow creation: <10ms
- Average step transition: <5ms
- Database: Single PostgreSQL instance

---

## CI/CD Integration

### GitHub Actions Workflow

```yaml
name: Test
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-elixir@v1
        with:
          elixir-version: 1.18
          otp-version: 27

      - run: mix deps.get
      - run: mix format --check-formatted
      - run: mix credo --strict
      - run: mix test
      - run: mix test --cover
      - run: mix dialyzer
      - run: mix docs
```

### Local Development Commands

```bash
# Run all tests
mix test

# Run with coverage report
mix test --cover

# Run specific test file
mix test test/ash_jobs/dsl/sections_test.exs

# Run with verbose output
mix test --trace

# Check code quality
mix format --check-formatted
mix credo --strict
mix dialyzer

# Build documentation
mix docs
```

---

## Implementation Checklist

Before each feature/component:

- [ ] Write test first (RED phase)
- [ ] Test fails as expected
- [ ] Implement minimum code (GREEN phase)
- [ ] All tests pass
- [ ] Refactor if needed (REFACTOR phase)
- [ ] Tests still pass
- [ ] Add edge case tests
- [ ] Add error scenario tests
- [ ] Update documentation
- [ ] Verify coverage >95%
- [ ] Check Dialyzer
- [ ] Check Credo

Before component merge:

- [ ] All unit tests passing
- [ ] All integration tests passing
- [ ] Coverage >95%
- [ ] No compiler warnings
- [ ] Code formatted
- [ ] Credo passes (strict)
- [ ] Documentation updated
- [ ] Performance benchmarks acceptable

---

## Document Cross-References

This overview document references two detailed guides:

1. **testing_strategy.md** - Complete testing patterns and strategies
2. **ash_specific_testing_guidance.md** - Elixir/Ash best practices

**For specific topics:**

- DSL testing → See testing_strategy.md §1
- Transformer testing → See ash_specific_testing_guidance.md §2
- Integration testing → See testing_strategy.md §6
- Error testing → See testing_strategy.md §10
- Performance testing → See testing_strategy.md §9
- CI/CD setup → See testing_strategy.md §12

---

## Next Steps

1. **Create test/support/ directory** with test helpers
2. **Implement DSL entity tests** (sections_test.exs, step_test.exs)
3. **Implement transformer tests** (integrate_state_machine_test.exs, etc.)
4. **Implement verifier tests** (validate_workflow_test.exs)
5. **Implement integration tests** (workflow_execution_test.exs, etc.)
6. **Add property-based tests** (workflow_generation_test.exs)
7. **Set up CI/CD pipeline** (GitHub Actions)
8. **Verify coverage reaches 95%+**

---

## Summary

This testing strategy provides:

✓ **Comprehensive coverage** of all component types  
✓ **Specific patterns** for each testing scenario  
✓ **Clear quality gates** at multiple levels  
✓ **Ash-specific guidance** for framework integration  
✓ **Performance expectations** and benchmarks  
✓ **CI/CD integration** ready to implement

**Total test effort:** ~200 tests across:

- 80+ unit tests (fast, isolated)
- 50+ integration tests (full workflow)
- 10+ property-based tests (invariants)
- 100+ assertions per component

**Timeline:** 2-3 weeks for comprehensive test suite  
**Target coverage:** 95%+ code coverage, 85%+ branch coverage  
**Quality:** Production-ready testing standards

---

**Status:** ✓ Ready for Breakdown Phase Implementation  
**Last Updated:** 2025-10-24  
**Confidence Level:** HIGH - Based on Ash ecosystem best practices
