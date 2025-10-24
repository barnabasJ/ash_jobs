# AshJobs Testing Strategy - Elixir/Ash Specific Guidance

**Document:** Specialized Testing Guidance for Ash Framework Extensions  
**Focus Areas:** Spark DSL testing, transformer patterns, ash_state_machine integration  
**Audience:** Elixir developers implementing library features  

---

## Elixir-Specific Best Practices

### 1. Spark DSL Testing Fundamentals

#### Understanding Spark.Dsl.State

```elixir
# The core type you'll be testing
defmodule Spark.Dsl.State do
  defstruct [
    :module,          # The resource module being compiled
    :operations,      # List of accumulated DSL operations
    :path,           # Current DSL section path [:workflow, :step]
    :sectioned,      # Sections defined so far
    :extension,      # Extension module using this DSL
    # ... other fields
  ]
end
```

#### Key Functions You'll Use

```elixir
# Get option value from DSL state
Spark.Dsl.Transformer.get_option(dsl_state, [:workflow, :steps])
# Returns: {:ok, value} or :error

# Get section from DSL state
Spark.Dsl.Transformer.get_section(dsl_state, [:state_machine])
# Returns: {:ok, section} or nil

# Get entities in section
Spark.Dsl.Transformer.get_entities(dsl_state, [:state_machine, :transitions])
# Returns: list of entities
```

#### Testing DSL Entity Definitions

```elixir
defmodule AshJobs.Dsl.Entities.StepTest do
  use ExUnit.Case, async: true
  
  # Spark entities are defined with Spark.Dsl.Entity
  # Test the entity schema itself
  
  test "step entity schema requires action" do
    # Spark validates at compilation time
    # You test by attempting to compile invalid DSL
    
    assert_compile_error(fn ->
      compile_resource("""
      defmodule TestResource do
        use Ash.Resource, extensions: [AshJobs]
        
        workflow do
          step :my_step do
            # Missing action - should fail
            on_success :completed
          end
        end
      end
      """)
    end)
  end
  
  test "step entity schema accepts all documented options" do
    # Test that all valid options are accepted
    resource = compile_resource("""
    defmodule TestResource do
      use Ash.Resource, extensions: [AshJobs]
      
      workflow do
        step :my_step do
          action :my_action
          on_success :next_step
          on_error :error_handler
          queue :default
          timeout_seconds 30
          retry_attempts 3
          trigger true
        end
      end
    end
    """)
    
    # Verify by introspection
    workflow = AshJobs.Info.workflow!(resource)
    step = Enum.find(workflow.steps, & &1.name == :my_step)
    
    assert step.action == :my_action
    assert step.queue == :default
    assert step.timeout_seconds == 30
  end
end
```

### 2. Transformer Testing Patterns for Ash

#### Pattern: Testing State Machine Generation

```elixir
defmodule AshJobs.Transformers.IntegrateStateMachineTest do
  use ExUnit.Case, async: true
  
  describe "state machine transformer" do
    test "generates correct state machine DSL section" do
      # 1. Create test resource with workflow
      {resource, dsl_state} = setup_test_resource("""
      workflow do
        step :step_one do
          action :act_one
          on_success :step_two
          on_error :error_step
        end
        
        step :step_two do
          action :act_two
          on_success :completed
        end
        
        step :error_step do
          action :handle_error
          on_complete :failed
        end
      end
      """)
      
      # 2. Run the transformer
      {:ok, transformed_state} = 
        AshJobs.Transformers.IntegrateStateMachine.transform(dsl_state)
      
      # 3. Verify state_machine DSL was generated
      assert has_state_machine?(transformed_state)
      
      # 4. Extract and verify states
      states = get_state_machine_states(transformed_state)
      assert Enum.any?(states, & &1.name == :step_one)
      assert Enum.any?(states, & &1.name == :step_two)
      assert Enum.any?(states, & &1.name == :error_step)
      
      # 5. Verify terminal states were added
      assert Enum.any?(states, & &1.name == :completed)
      assert Enum.any?(states, & &1.name == :failed)
      assert Enum.any?(states, & &1.name == :cancelled)
      
      # 6. Verify transitions were generated
      transitions = get_state_machine_transitions(transformed_state)
      
      # Should have: :step_one -> :step_two (success)
      assert Enum.any?(transitions, fn t ->
        t.from == :step_one and t.to == :step_two
      end)
      
      # Should have: :step_one -> :error_step (error)
      assert Enum.any?(transitions, fn t ->
        t.from == :step_one and t.to == :error_step
      end)
    end
    
    test "respects custom state_attribute option" do
      # Test that custom state_attribute is used instead of :state
      resource = compile_resource("""
      workflow do
        state_attribute :workflow_state
        
        step :my_step do
          action :my_action
          on_success :completed
        end
      end
      """)
      
      state_machine = AshJobs.Info.state_machine!(resource)
      assert state_machine.state_attribute == :workflow_state
    end
    
    test "skips generation if state_machine already defined" do
      # Test idempotency - don't overwrite existing state_machine
      resource = compile_resource("""
      state_machine do
        state_attribute :custom_state
      end
      
      workflow do
        step :my_step do
          action :my_action
          on_success :completed
        end
      end
      """)
      
      state_machine = AshJobs.Info.state_machine!(resource)
      assert state_machine.state_attribute == :custom_state
    end
  end
  
  # Helper functions
  defp has_state_machine?(dsl_state) do
    case Spark.Dsl.Transformer.get_section(dsl_state, [:state_machine]) do
      {:ok, _} -> true
      :error -> false
    end
  end
  
  defp get_state_machine_states(dsl_state) do
    {:ok, section} = Spark.Dsl.Transformer.get_section(dsl_state, [:state_machine])
    Spark.Dsl.Transformer.get_entities(section, [:states]) || []
  end
  
  defp get_state_machine_transitions(dsl_state) do
    {:ok, section} = Spark.Dsl.Transformer.get_section(dsl_state, [:state_machine])
    Spark.Dsl.Transformer.get_entities(section, [:transitions]) || []
  end
end
```

### 3. Ash Resource Compilation Testing

#### Pattern: Testing Full Resource Compilation

```elixir
defmodule AshJobs.CompilationTest do
  use ExUnit.Case
  
  # Helper to compile resources in tests
  defp compile_resource(code_string) do
    quote_ast = Code.string_to_quoted!(code_string)
    
    {module, _} = Code.eval_quoted(quote_ast)
    
    # Return the compiled module for introspection
    module
  end
  
  test "workflow compiles without errors" do
    # Most comprehensive test - actual compilation
    resource = compile_resource("""
    defmodule MyWorkflow do
      use Ash.Resource, extensions: [AshJobs, AshStateMachine, AshOban]
      
      attributes do
        attribute :name, :string
      end
      
      workflow do
        step :validate do
          action :validate_action
          on_success :process
          on_error :failed_validation
        end
        
        step :process do
          action :process_action
          on_success :completed
        end
        
        step :failed_validation do
          action :handle_validation_error
          on_complete :failed
        end
      end
      
      actions do
        create :create
        update :validate_action
        update :process_action
        update :handle_validation_error
      end
    end
    """)
    
    # Verify resource compiled successfully by checking its properties
    assert Ash.Resource.Info.resource?(resource)
    
    # Verify extensions were applied
    assert AshJobs.Info.workflow!(resource) != nil
    assert Ash.Resource.Info.has_extension(resource, AshStateMachine)
    assert Ash.Resource.Info.has_extension(resource, AshOban)
    
    # Verify workflow info was generated
    workflow = AshJobs.Info.workflow!(resource)
    assert workflow.steps != nil
    assert Enum.any?(workflow.steps, & &1.name == :validate)
  end
end
```

### 4. Testing with Ash.Resource.Info

#### Key Introspection Functions

```elixir
# Get attributes
Ash.Resource.Info.attributes(resource)
# Returns: list of attributes with names, types, defaults

# Get actions
Ash.Resource.Info.actions(resource)
# Returns: list of actions with configurations

# Check if extension is present
Ash.Resource.Info.has_extension(resource, AshStateMachine)
# Returns: boolean

# Get extension-specific info (what you implement)
AshJobs.Info.workflow!(resource)
# Returns: workflow struct with all configuration

# For AshStateMachine
Ash.Resource.Info.state_machines(resource)
# Returns: list of state machine configurations
```

### 5. Error Testing in Ash

#### Pattern: Testing Compilation Errors

```elixir
defmodule AshJobs.ErrorTest do
  use ExUnit.Case
  
  test "provides clear error for missing action" do
    assert_raise Ash.Error.DslError, 
      ~r/action.*not found|required/, fn ->
      compile_resource("""
      defmodule BadWorkflow do
        use Ash.Resource, extensions: [AshJobs]
        
        workflow do
          step :my_step do
            action :nonexistent_action
            on_success :completed
          end
        end
      end
      """)
    end
  end
  
  test "provides clear error for circular dependency" do
    assert_raise Ash.Error.DslError, 
      ~r/circular|cycle|loop/, fn ->
      compile_resource("""
      defmodule BadWorkflow do
        use Ash.Resource, extensions: [AshJobs]
        
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
      end
      """)
    end
  end
  
  test "error messages are helpful and actionable" do
    error = catch_error(fn ->
      compile_resource("""
      defmodule BadWorkflow do
        use Ash.Resource, extensions: [AshJobs]
        
        workflow do
          step :my_step do
            on_success :completed
            # Missing action!
          end
        end
      end
      """)
    end)
    
    # Error should:
    # 1. Say what's wrong
    assert error.message =~ "action"
    
    # 2. Say where it went wrong
    assert error.message =~ ":my_step"
    
    # 3. Suggest how to fix it
    assert error.message =~ "define" or error.message =~ "add"
  end
  
  defp catch_error(func) do
    try do
      func.()
      flunk("Expected error but compilation succeeded")
    rescue
      e in [Ash.Error.DslError, CompileError] -> e
    end
  end
end
```

---

## ash_state_machine Integration Testing

### Understanding State Machine Integration

```elixir
# What ash_state_machine provides:
# 1. State attribute (defaults to :state)
# 2. Transition enforcement (only valid transitions allowed)
# 3. State chart generation
# 4. Automatic state validation

# Your transformers must:
# 1. Generate state_machine DSL section
# 2. Define all states (steps + terminal states)
# 3. Define all valid transitions (on_success + on_error routes)
# 4. Set state_attribute (defaults to :state)
```

### Testing State Transitions

```elixir
defmodule AshJobs.Integration.StateTransitionTest do
  use ExUnit.Case
  
  setup do
    {:ok, %{
      resource: compile_workflow_resource()
    }}
  end
  
  test "state transitions work correctly", %{resource: resource} do
    # 1. Create initial record
    {:ok, record} = Ash.create!(resource, %{})
    
    # Should start in first step state
    assert record.state == :step_one
    
    # 2. Execute step one action
    {:ok, updated} = Ash.update!(record, :step_one_action)
    
    # Should transition to next state
    assert updated.state == :step_two
    
    # 3. Execute step two action
    {:ok, final} = Ash.update!(updated, :step_two_action)
    
    # Should transition to completed
    assert final.state == :completed
  end
  
  test "invalid transitions are rejected" do
    {:ok, record} = Ash.create!(resource, %{})
    
    # Try to transition directly from :step_one to :completed
    # This should fail because no transition exists
    assert_raise Ash.Error.Invalid, fn ->
      Ash.update!(record, :invalid_transition_action)
    end
  end
  
  test "error transitions route to error handlers" do
    {:ok, record} = Ash.create!(resource, %{})
    
    # Mock a failing step
    # Should transition to error handler step
    # This is handled by Oban trigger's on_error option
  end
  
  defp compile_workflow_resource do
    # Return a compiled resource with workflow
  end
end
```

---

## ash_oban Integration Testing

### Testing Oban Trigger Generation

```elixir
defmodule AshJobs.Integration.ObanIntegrationTest do
  use ExUnit.Case
  
  describe "oban integration" do
    test "triggers are generated for each step" do
      resource = compile_workflow_resource()
      
      # Get all triggers defined in resource
      triggers = Ash.Resource.Info.triggers(resource)
      
      # Should have trigger for each automatic step
      trigger_names = Enum.map(triggers, & &1.name)
      assert :step_one in trigger_names
      assert :step_two in trigger_names
      
      # Should not have trigger for trigger: false steps
      assert :manual_step not in trigger_names
    end
    
    test "triggers call correct actions" do
      resource = compile_workflow_resource()
      
      triggers = Ash.Resource.Info.triggers(resource)
      
      step_one_trigger = Enum.find(triggers, & &1.name == :step_one)
      assert step_one_trigger.action == :step_one_action
    end
    
    test "triggers fire with correct conditions" do
      # Use Oban.Testing to verify trigger behavior
      Oban.Testing.with_testing_mode(:inline) do
        {:ok, record} = Ash.create!(resource, %{})
        
        # Oban trigger should fire automatically
        # When state is :step_one
        
        # Job should progress to next step
        {:ok, updated} = Ash.read_one(resource, record.id)
        assert updated.state != :step_one
      end
    end
    
    test "manual pause steps (trigger: false) don't auto-fire" do
      # Manual steps should not generate Oban triggers
      # They must be advanced manually
    end
  end
end
```

### Using Oban.Testing

```elixir
# In your test environment configuration
config :my_app, Oban, testing: :manual

# Or use with_testing_mode in specific tests
test "workflow progresses with Oban" do
  Oban.Testing.with_testing_mode(:inline) do
    # Triggers fire synchronously in inline mode
    {:ok, job} = Ash.create!(TestWorkflow, %{})
    
    # Automatically progresses through first step
    {:ok, updated} = Ash.read_one(TestWorkflow, job.id)
    assert updated.state == :step_two  # Progressed!
  end
end

# Or in manual mode, execute jobs manually
test "manually execute workflow steps" do
  {:ok, job} = Ash.create!(TestWorkflow, %{})
  
  # Get pending jobs for this record
  pending_jobs = Oban.select_jobs(TestWorkflow, job.id)
  
  # Execute them manually
  Enum.each(pending_jobs, fn oban_job ->
    Oban.Testing.perform_job(oban_job)
  end)
  
  # Verify progress
  {:ok, updated} = Ash.read_one(TestWorkflow, job.id)
  assert updated.state == :completed
end
```

---

## Testing Best Practices from Ash Ecosystem

### 1. Use Ash.Test.Helpers

```elixir
# Include these in your test files
import Ash.Test.Helpers

# Useful functions:
# - assert_has_error/2
# - assert_valid/1
# - assert_invalid/1
# - require_ash_types!/0

defmodule MyTest do
  use ExUnit.Case
  import Ash.Test.Helpers
  
  test "validates resource" do
    resource = MyWorkflow
    require_ash_types!(resource)
    
    {:ok, record} = Ash.create!(resource, %{})
    assert_valid(record)
  end
end
```

### 2. Use ExUnit.Case with async: true

```elixir
defmodule AshJobs.TransformerTest do
  use ExUnit.Case, async: true
  # ↑ This makes tests run in parallel
  # Safe for transformer and unit tests
  # Not safe for integration tests (database conflicts)
end

defmodule AshJobs.Integration.WorkflowTest do
  use ExUnit.Case
  # ↑ No async: true for integration tests
  # Database operations need serialization
end
```

### 3. Test Resource Compilation with Proper Setup

```elixir
defmodule AshJobs.ResourceCompilationTest do
  use ExUnit.Case
  
  # Helper to safely compile resources
  def compile_test_resource(code_string) do
    # Use Code.eval_quoted to avoid namespace pollution
    {module, _} = Code.eval_quoted(
      Code.string_to_quoted!(code_string),
      []
    )
    module
  end
  
  # Or use ExUnit setup for shared resources
  setup do
    {:ok, %{
      resource: compile_test_resource(~S"""
      defmodule TestWorkflow do
        use Ash.Resource, extensions: [AshJobs]
        # ...
      end
      """)
    }}
  end
end
```

### 4. Document Ash-Specific Test Patterns

```elixir
# In test comments, explain WHY you're testing this way
# Ash has some non-obvious patterns

defmodule AshJobs.StateTransitionTest do
  use ExUnit.Case
  
  test "state transitions are enforced by ash_state_machine" do
    # ash_state_machine validates allowed transitions at runtime.
    # We test that our transformer generates correct transition definitions
    # so that invalid transitions are rejected.
    
    {:ok, record} = Ash.create!(TestWorkflow, %{})
    assert record.state == :step_one
    
    # This transition is valid (defined in state_machine)
    {:ok, updated} = Ash.update!(record, :step_one_action)
    assert updated.state == :step_two
    
    # This transition is invalid (not defined)
    # ash_state_machine should reject it
    assert_raise Ash.Error.Invalid, fn ->
      Ash.update!(updated, :invalid_action)
    end
  end
end
```

---

## Key Ash Framework Testing Considerations

### Don't Test These (Ash Already Does)

- Ash's core change mechanism
- Ash's attribute type validation
- ash_state_machine's transition logic
- Oban's job processing
- Database persistence (basic operations)

**Instead, test YOUR CODE:**

- DSL definitions you create
- Transformers you write
- Verifiers you implement
- Your routing logic (Change module)
- Integration between your code and Ash

### DO Test These

```elixir
# 1. Your DSL sections and entities
defmodule AshJobs.Dsl.Entities.StepTest do
  # ✓ Test that Step entity accepts correct options
  # ✓ Test that required fields are enforced
  # ✓ Test default values
end

# 2. Your transformers (code generation)
defmodule AshJobs.Transformers.IntegrateStateMMachineTest do
  # ✓ Test that state_machine DSL is generated correctly
  # ✓ Test that states and transitions match workflow
  # ✓ Test error detection
end

# 3. Your verifiers (validation)
defmodule AshJobs.Verifiers.ValidateWorkflowTest do
  # ✓ Test all validation rules
  # ✓ Test error messages
end

# 4. End-to-end workflow behavior
defmodule AshJobs.Integration.WorkflowTest do
  # ✓ Test complete workflows execute correctly
  # ✓ Test state transitions
  # ✓ Test error handling
  # ✓ Test manual pause points
end

# 5. Your business logic integration
defmodule AshJobs.Integration.CustomActionTest do
  # ✓ Test how your Change module integrates with user's actions
  # ✓ Test that routing happens after user's changes
end
```

---

## Debugging Failed Tests in Ash

### Common Issues and Solutions

#### Issue 1: "DSL Section Not Found"

```elixir
# Problem: Your transformer tries to get a section that doesn't exist yet
# Solution: Check transformer ordering dependencies

# In ash_jobs.ex
use Spark.Dsl.Extension,
  transformers: [
    AshJobs.Transformers.BuildWorkflow,
    {AshJobs.Transformers.IntegrateStateMachine,
     after: [AshJobs.Transformers.BuildWorkflow]},
    # ^ Specifies dependency order
```

#### Issue 2: "Invalid Attribute Type"

```elixir
# Problem: Generated attribute has wrong type
# Solution: Check type conversion in transformer

# Don't do this (incorrect type):
Spark.Dsl.Entity{
  attributes: [state: :string]  # ✗ Wrong type
}

# Do this (correct type):
Spark.Dsl.Entity{
  attributes: [state: :atom]    # ✓ Correct type
}
```

#### Issue 3: "State Machine Conflicts"

```elixir
# Problem: User already defined state_machine
# Solution: Check if it exists before generating

# In transformer:
existing_sm = Spark.Dsl.Transformer.get_section(dsl_state, [:state_machine])

case existing_sm do
  {:ok, sm} ->
    # Already exists - validate and skip
    validate_compatible(sm)
  :error ->
    # Doesn't exist - generate it
    generate_state_machine(dsl_state)
end
```

#### Issue 4: "Tests Pass Locally but Fail in CI"

```elixir
# Common causes:
# 1. Database not available - use config :ash_jobs, :test_mode, true
# 2. Test order dependent - use async: false for integration tests
# 3. Missing async cleanup - restart application between tests

# Solution in setup:
setup do
  # Restart Oban application if needed
  :ok = Application.stop(:oban)
  :ok = Application.start(:oban)
  
  :ok
end
```

---

## Summary Checklist: Ash-Specific Testing

- [ ] Unit tests with `async: true` for transformers
- [ ] Integration tests without async for database operations
- [ ] Use `Oban.Testing.with_testing_mode(:inline)` for testing workflow execution
- [ ] Test DSL compilation errors with `Code.compile_quoted` and `assert_raise`
- [ ] Use `Ash.Resource.Info.*` functions to verify generated code
- [ ] Document WHY you're testing ASH-specific behavior
- [ ] Mock only what's external (not Ash, not our dependencies)
- [ ] Test your code, not Ash's code
- [ ] Check transformer ordering with `after:` and `before:` dependencies
- [ ] Verify both happy paths and error paths

---

**These patterns align with established Ash ecosystem conventions.**  
**When in doubt, check ash_state_machine and ash_oban test suites for examples.**

