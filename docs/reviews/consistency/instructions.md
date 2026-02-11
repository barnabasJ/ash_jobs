# Consistency Review Instructions

## Overview

Consistency reviews ensure code follows established patterns, naming
conventions, and architectural decisions throughout the codebase. This creates a
predictable, maintainable codebase that's easy for contributors to understand
and extend.

## Review Checklist

### 1. Naming Conventions

- [ ] **Module Names**

  - CamelCase for modules (`AshJobs.Dsl.Entities.Step`)
  - snake_case for file names matching module names
  - Clear namespace hierarchy

- [ ] **Function Names**

  - snake_case for all functions
  - Bang functions (`!`) raise on error, non-bang return tuples
  - Private functions use `defp`
  - Consistent verb choices (get vs fetch, create vs build)

- [ ] **Variable Names**
  - snake_case throughout
  - Descriptive, not cryptic
  - Consistent abbreviations (e.g., `attr` for attribute)
  - Accumulator pattern: `acc_state`, `acc_result`

### 2. Documentation Patterns

- [ ] **Module Documentation**

  - Every module has `@moduledoc`
  - Structure: Purpose → Responsibilities → Examples
  - Include architectural context for transformers/verifiers

- [ ] **Function Documentation**

  - All public functions have `@doc`
  - Include examples using consistent format
  - Describe return types and behaviors
  - Private functions typically undocumented

- [ ] **Example Format**

  ```elixir
  @doc """
  Brief description of what function does.

  ## Examples

      Module.function(arg)
      #=> expected_output
  """
  ```

### 3. Code Organization

- [ ] **File Structure**

  - One module per file
  - File paths match module names
  - Logical grouping in directories (`dsl/`, `transformers/`, `verifiers/`)

- [ ] **Module Structure Order**
  1. Module definition
  2. `@moduledoc`
  3. `use` statements
  4. `alias`, `import`, `require`
  5. `@type` definitions
  6. Module attributes (`@constants`)
  7. Struct definitions (`defstruct`)
  8. Public API functions
  9. Private helper functions

### 4. Error Handling

- [ ] **Return Type Consistency**

  - `:error` for simple failures
  - `{:ok, value}` for successes
  - `{:error, exception}` for detailed failures
  - Framework-specific errors (e.g., `Spark.Error.DslError`)

- [ ] **Validation Patterns**
  - Use `with` for sequential validations
  - Consistent error message formatting (prefer heredocs)
  - Include helpful context in error messages

### 5. Test Organization

- [ ] **Test File Naming**

  - `*_test.exs` suffix
  - Mirror source structure (`lib/foo.ex` → `test/foo_test.exs`)
  - Integration tests in `test/integration/`

- [ ] **Test Structure**
  - Use `describe` blocks for grouping
  - Clear test names describing expected behavior
  - Setup blocks for common initialization
  - `async: false` for database-dependent tests

### 6. Framework Integration

#### For Ash/Spark Projects:

- [ ] **DSL Integration**

  - Use entity builders: `Spark.Dsl.Transformer.build_entity`
  - Proper option handling: `Spark.Dsl.Transformer.get_option`
  - Explicit transformer ordering: `before?/1`, `after?/1`

- [ ] **Resource Patterns**
  - Consistent use of `Ash.Resource.Info` for introspection
  - Proper change/preparation/validation modules

## Common Inconsistencies to Check

### Constants and Magic Values

**Problem:** Same constants defined in multiple places

**Example:**

```elixir
# Module A
@terminal_states [:completed, :failed, :cancelled]

# Module B
terminal_states = [:completed, :failed, :cancelled]  # Duplicate!
```

**Fix:** Extract to shared module or configuration

### Error Message Formatting

**Problem:** Mixed use of inline strings and heredocs

**Standard:** Use heredocs for multi-line error messages:

```elixir
{:error,
 Spark.Error.DslError.exception(
   module: __MODULE__,
   message: """
   Clear error description.

   Additional context here.
   Helpful suggestions.
   """
 )}
```

### Comment Styles

**Standard:**

- Single-line comments for brief explanations
- Multi-line comments for algorithms/complex logic
- Algorithm descriptions before complex functions

### Function Ordering

**Standard:** Group related functions, order by:

1. Primary public API
2. Supporting public functions
3. Private helpers (in order of usage)

## Review Process

1. **Read codebase** - Start with main module, follow imports
2. **Identify patterns** - Note naming, organization, documentation styles
3. **Check consistency** - Verify patterns are applied uniformly
4. **Document deviations** - Note any inconsistencies with reasons
5. **Suggest standardization** - Provide concrete examples for fixes
6. **Update best practices** - Add new patterns discovered

## Tools to Use

- `mix format --check-formatted` - Verify code formatting
- `mix credo --strict` - Check style guidelines
- `grep -r "pattern"` - Find usage patterns
- Visual inspection - Some patterns need human judgment

## Output Format

### Review Report Structure

1. **Overall Assessment** - High-level summary
2. **Strengths** - Consistent patterns to maintain
3. **Areas for Improvement** - Specific inconsistencies found
4. **Recommendations** - Prioritized action items
5. **Best Practices Identified** - Patterns to document/replicate

### Priority Levels

- **High:** Affects code correctness or maintainability
- **Medium:** Affects readability or contributor experience
- **Low:** Minor cosmetic improvements

## Examples from ash_jobs

### Excellent Pattern: Bang Function Consistency

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
    steps -> {:ok, %{steps: steps, state_attribute: state_attr}}
  end
end
```

### Improvement Needed: Duplicate Constants

**Before:**

```elixir
# In multiple files
[:completed, :failed, :cancelled]
[:completed, :failed, :cancelled]
[:completed, :failed, :cancelled]
```

**After:**

```elixir
# In AshJobs.Constants or main module
defmodule AshJobs do
  @terminal_states [:completed, :failed, :cancelled]
  def terminal_states, do: @terminal_states
end

# In other modules
unless state in AshJobs.terminal_states() do
```

## Memory Integration

Before reviewing:

- Check memories for previous consistency issues
- Review project-specific patterns

After reviewing:

- Store inconsistency patterns discovered
- Update best practices for this codebase
- Document any codebase-specific conventions
