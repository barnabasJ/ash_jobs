# Consistency Best Practices - ash_jobs

## Overview

This document captures the established patterns and best practices identified in
the ash_jobs codebase. These patterns should be followed when contributing to
maintain consistency.

## Naming Conventions

### Module Names

**Pattern:** Descriptive namespaces with clear hierarchy

```elixir
AshJobs                              # Root module
AshJobs.Dsl.Entities.Step           # DSL entity definitions
AshJobs.Transformers.BuildWorkflow  # Compile-time transformations
AshJobs.Verifiers.ValidateWorkflow  # Compile-time validations
```

**File Structure:**

- `lib/ash_jobs.ex` → Main extension module
- `lib/ash_jobs/dsl/` → DSL definitions
- `lib/ash_jobs/transformers/` → Spark transformers
- `lib/ash_jobs/verifiers/` → Spark verifiers

### Function Names

**Pattern:** Bang functions raise, non-bang return tuples

```elixir
# Raises on error
def workflow!(resource) do
  case workflow(resource) do
    {:ok, workflow} -> workflow
    :error -> raise "No workflow defined for #{inspect(resource)}"
  end
end

# Returns tuple
def workflow(resource) do
  case steps(resource) do
    [] -> :error
    steps -> {:ok, %{steps: steps}}
  end
end
```

**Common Verbs:**

- `get_*` - Retrieve single item (returns tuple)
- `list_*` or plural - Retrieve multiple items
- `build_*` - Construct data structure
- `generate_*` - Create DSL entities
- `validate_*` - Check conditions (returns `:ok` or `{:error, ...}`)

### Variable Names

**Established Abbreviations:**

- `dsl_state` - Spark DSL state
- `acc_state` - Accumulator for DSL state
- `state_attr` - State attribute name
- `opts` - Options keyword list

**Accumulator Pattern:**

```elixir
Enum.reduce(items, dsl_state, fn item, acc_state ->
  transform(acc_state, item)
end)
```

## Documentation Standards

### Module Documentation Structure

```elixir
defmodule AshJobs.Example do
  @moduledoc """
  Brief one-line description.

  Detailed explanation of purpose and responsibilities.

  ## Architecture Notes

  How this fits into the system (for transformers/verifiers).

  ## Examples

      use Ash.Resource,
        extensions: [AshJobs]

      workflow do
        step :example do
          action :do_work
          on_success :completed
        end
      end
  """
end
```

### Function Documentation Format

```elixir
@doc """
Returns the workflow configuration for a resource.

Returns :error if no workflow is defined.

## Examples

    case AshJobs.Info.workflow(MyApp.FulfillmentJob) do
      {:ok, workflow} -> # Use workflow
      :error -> # No workflow
    end
"""
def workflow(resource) do
  # Implementation
end
```

### Inline Comments

**For Complex Algorithms:**

```elixir
# DFS cycle detection using three colors:
# - white (unvisited)
# - gray (visiting - on current path)
# - black (visited - finished)
defp find_cycle_dfs(nodes, graph, state, path) do
  # Implementation
end
```

**For Business Logic:**

```elixir
# Error handlers use on_complete and have no on_success
# Regular steps use on_success
defp is_error_handler?(step) do
  step.on_complete != nil && step.on_success == nil
end
```

## Code Organization

### Module Structure Order

1. **Module definition**

   ```elixir
   defmodule AshJobs.Example do
   ```

2. **Module documentation**

   ```elixir
   @moduledoc """..."""
   ```

3. **Use statements**

   ```elixir
   use Spark.Dsl.Transformer
   ```

4. **Aliases and imports**

   ```elixir
   alias AshJobs.Dsl.Entities.Step
   require Logger
   ```

5. **Type definitions**

   ```elixir
   @type t :: %__MODULE__{...}
   ```

6. **Module attributes (constants)**

   ```elixir
   @terminal_states [:completed, :failed, :cancelled]
   ```

7. **Struct definitions**

   ```elixir
   defstruct [:name, :action, queue: :default]
   ```

8. **Public API functions**

   ```elixir
   def workflow!(resource), do: ...
   def workflow(resource), do: ...
   ```

9. **Private helper functions**
   ```elixir
   defp validate_step_references(workflow), do: ...
   defp build_dependency_graph(workflow), do: ...
   ```

### Transformer Pattern

**Ordering Methods:**

```elixir
use Spark.Dsl.Transformer

# Explicit ordering relative to other transformers
def after?(AshJobs.Transformers.GenerateErrorActions), do: true
def after?(_), do: false

def before?(AshJobs.Transformers.IntegrateStateMachine), do: true
def before?(AshJobs.Transformers.IntegrateOban), do: true
def before?(_), do: false
```

**Transform Structure:**

```elixir
def transform(dsl_state) do
  # Get workflow configuration
  steps = Spark.Dsl.Extension.get_entities(dsl_state, [:workflow])

  if steps && length(steps) > 0 do
    # Perform transformation
    dsl_state = do_transformation(dsl_state, steps)
    {:ok, dsl_state}
  else
    # No workflow defined, skip
    {:ok, dsl_state}
  end
end
```

## Error Handling

### Return Type Patterns

**Simple failures:**

```elixir
def step(resource, step_name) do
  case Enum.find(steps(resource), &(&1.name == step_name)) do
    nil -> :error
    step -> {:ok, step}
  end
end
```

**Validation errors:**

```elixir
{:error,
 Spark.Error.DslError.exception(
   module: __MODULE__,
   message: """
   Clear description of the problem.

   Context and details here.

   Suggested fixes:
   - Option 1
   - Option 2
   """
 )}
```

**With clause validation:**

```elixir
with :ok <- validate_step_references(workflow),
     :ok <- validate_circular_dependencies(workflow),
     :ok <- validate_actions_exist(dsl_state, workflow) do
  :ok
end
```

### Error Message Standards

**Use heredocs for multi-line messages:**

```elixir
"""
Problem description in plain English.

Relevant details:
- Detail 1
- Detail 2

How to fix this:

    code example here
    showing the solution
"""
```

**Include context:**

- What went wrong
- Why it's a problem
- How to fix it
- Code examples when helpful

## Testing Patterns

### Test File Organization

**Mirror source structure:**

```
lib/ash_jobs/info.ex
test/ash_jobs/info_test.exs

lib/ash_jobs/transformers/build_workflow.ex
test/ash_jobs/transformers/build_workflow_test.exs
```

**Integration tests separate:**

```
test/integration/simple_workflow_test.exs
test/integration/branching_workflow_test.exs
```

### Test Structure

**Use describe blocks:**

```elixir
defmodule AshJobs.InfoTest do
  use ExUnit.Case, async: false

  import AshJobs.Test.CompilationHelpers

  setup do
    {:ok, resource} = compile_resource("...")
    {:ok, resource: resource}
  end

  describe "workflow!/1" do
    test "returns workflow configuration", %{resource: resource} do
      workflow = AshJobs.Info.workflow!(resource)
      assert workflow.state_attribute == :state
    end

    test "raises if no workflow defined" do
      assert_raise RuntimeError, fn ->
        AshJobs.Info.workflow!(no_workflow_resource)
      end
    end
  end

  describe "workflow/1" do
    test "returns {:ok, workflow} when defined", %{resource: resource} do
      assert {:ok, workflow} = AshJobs.Info.workflow(resource)
    end
  end
end
```

**Integration test pattern:**

```elixir
defmodule AshJobs.Integration.SimpleWorkflowTest do
  @moduledoc """
  Comprehensive tests for SimpleWorkflow.

  SimpleWorkflow is a minimal two-state workflow.
  Tests cover happy path, state transitions, and automatic job queuing.
  """

  use AshJobs.DataCase, async: false
  use Oban.Testing, repo: AshJobs.TestRepo

  alias AshJobs.TestResources.SimpleWorkflow

  setup do
    TestRepo.delete_all(SimpleWorkflow)
    :ok
  end

  describe "happy path" do
    test "workflow completes successfully from start to finish" do
      {:ok, job} = SimpleWorkflow.create(%{name: "test"})

      Oban.Testing.with_testing_mode(:inline, fn ->
        AshOban.run_trigger(job, :process)
      end)

      job = SimpleWorkflow.get_by_id!(job.id)
      assert job.state == :completed
    end
  end
end
```

## Spark/Ash Integration

### Entity Building

**Use proper builders for validation:**

```elixir
{:ok, entity} = Spark.Dsl.Transformer.build_entity(
  AshOban,
  [:oban, :triggers],
  :trigger,
  name: :step_name,
  action: :action_name,
  queue: :default
)

Spark.Dsl.Transformer.add_entity(
  dsl_state,
  [:oban, :triggers],
  entity
)
```

**Don't use raw structs:**

```elixir
# ❌ Bad - bypasses validation
trigger = %AshOban.Trigger{name: :step_name}

# ✓ Good - validates via builder
{:ok, trigger} = Spark.Dsl.Transformer.build_entity(...)
```

### Option Handling

```elixir
# Get option with default
state_attr = Spark.Dsl.Transformer.get_option(
  dsl_state,
  [:workflow],
  :state_attribute
) || :state

# Set option
dsl_state = Spark.Dsl.Transformer.set_option(
  dsl_state,
  [:state_machine],
  :initial_states,
  [initial_state]
)
```

## Known Issues to Avoid

### 1. Duplicate Constants

**❌ Don't duplicate terminal states:**

```elixir
# In multiple files
@terminal_states [:completed, :failed, :cancelled]
terminal_states = [:completed, :failed, :cancelled]
```

**✓ Extract to shared location** (TODO: Implement this)

### 2. Error Message Formatting

**❌ Don't use inline strings for multi-line errors:**

```elixir
raise "Failed to build: #{inspect(error)}"
```

**✓ Use heredocs:**

```elixir
raise """
Failed to build error handler action #{action_name}:
#{inspect(error)}
"""
```

### 3. Entity Removal

**⚠️ Spark's `remove_entity` may not exist in all versions:**

```elixir
try do
  Spark.Dsl.Transformer.remove_entity(dsl_state, [:actions], fn action ->
    action.name == action_name
  end)
rescue
  _ -> dsl_state
end
```

## Formatter Configuration

The project uses:

- Spark.Formatter plugin for DSL formatting
- Import deps from ash, ash_state_machine, ash_oban
- Standard Elixir formatting rules

**Run before committing:**

```bash
mix format
```

## Credo Rules

Follow Credo's strict mode guidelines:

```bash
mix credo --strict
```

**Common issues to avoid:**

- Long functions (>60 lines)
- Complex cyclomatic complexity
- Nested conditionals (>3 levels)
- Module documentation missing

## Summary of Key Patterns

1. **Bang vs Non-Bang:** Consistent return types across codebase
2. **Documentation:** Every public function documented with examples
3. **Error Handling:** Use `with` for validation chains, heredocs for messages
4. **Testing:** Mirror source structure, use describe blocks, comprehensive
   integration tests
5. **Transformers:** Explicit ordering, check for workflow existence
6. **Entity Building:** Always use Spark builders, never raw structs
7. **Module Structure:** Consistent ordering of sections

## References

- [Elixir Naming Conventions](https://hexdocs.pm/elixir/naming-conventions.html)
- [Ash Framework Docs](https://hexdocs.pm/ash/)
- [Spark DSL Documentation](https://hexdocs.pm/spark/)
- [Credo Style Guide](https://github.com/rrrene/elixir-style-guide)
