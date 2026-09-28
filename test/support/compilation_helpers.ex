defmodule AshJobs.Test.CompilationHelpers do
  @moduledoc """
  Helper functions for compiling test resources with DSL code.

  These helpers enable writing tests that verify transformer and verifier behavior
  by compiling resources with specific DSL configurations and inspecting the results.
  """

  @doc """
  Compiles a test resource with the provided DSL code.

  ## Parameters

    * `dsl_code` - String containing Elixir DSL code to inject into the resource

  ## Returns

    * `{:ok, module}` - Successfully compiled resource module
    * `{:error, reason}` - Compilation failed with reason

  ## Examples

      iex> {:ok, resource} = compile_resource(\"\"\"
      ...>   workflow do
      ...>     step :test_step do
      ...>       action :test_action
      ...>       on_success :completed
      ...>     end
      ...>   end
      ...>
      ...>   actions do
      ...>     defaults [:read]
      ...>     update :test_action, do: accept([])
      ...>   end
      ...> \"\"\")
      iex> function_exported?(resource, :spark_is, 0)
      true
  """
  def compile_resource(dsl_code) do
    # Generate unique module name to avoid conflicts
    module_name = :"TestResource#{System.unique_integer([:positive])}"

    # Add default attributes if not present in dsl_code
    default_attributes = """
    attributes do
      uuid_primary_key :id
    end
    """

    # Only add attributes if dsl_code doesn't already contain them
    dsl_with_config =
      if String.contains?(dsl_code, "attributes do") do
        dsl_code
      else
        default_attributes <> "\n" <> dsl_code
      end

    # Build full module code
    # Note: Only include AshJobs extension for testing the GenerateErrorActions transformer
    # AshStateMachine and AshOban will be tested with their own transformers (tasks 7 & 8)
    full_code = """
    defmodule #{module_name} do
      use Ash.Resource,
        domain: nil,
        extensions: [AshJobs]

      #{dsl_with_config}
    end
    """

    try do
      # Convert code string to AST
      quoted = Code.string_to_quoted!(full_code)

      # Evaluate the quoted code to define and compile the module
      # Code.eval_quoted returns {result, binding} where result is {:module, name, bytecode, return_value}
      {{:module, module, _bytecode, _return}, _binding} = Code.eval_quoted(quoted)

      {:ok, module}
    rescue
      error ->
        {:error, error}
    end
  end

  @doc """
  Compiles a resource and returns its DSL state.

  This is useful for testing transformers that modify the DSL state.

  ## Parameters

    * `dsl_code` - String containing Elixir DSL code

  ## Returns

    * `{:ok, dsl_state}` - Successfully compiled with DSL state
    * `{:error, reason}` - Compilation failed
  """
  def compile_resource_with_dsl_state(dsl_code) do
    case compile_resource(dsl_code) do
      {:ok, module} ->
        # Extract DSL state from compiled module
        dsl_state = Spark.Dsl.Extension.get_persisted(module, :dsl_state)
        {:ok, dsl_state}

      error ->
        error
    end
  end

  @doc """
  Compiles a resource and verifies it compiles without errors.

  This is useful for integration tests that just need to verify
  that valid DSL code compiles successfully.

  ## Parameters

    * `dsl_code` - String containing Elixir DSL code

  ## Returns

    * `:ok` - Compilation succeeded
    * `{:error, reason}` - Compilation failed
  """
  def assert_compiles(dsl_code) do
    case compile_resource(dsl_code) do
      {:ok, _module} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Compiles a resource and verifies it fails to compile.

  This is useful for testing validation logic that should reject
  invalid DSL configurations.

  ## Parameters

    * `dsl_code` - String containing Elixir DSL code

  ## Returns

    * `{:ok, error}` - Compilation failed as expected
    * `{:error, :unexpected_success}` - Compilation succeeded when it should have failed
  """
  def assert_compile_fails(dsl_code) do
    case compile_resource(dsl_code) do
      {:ok, _module} -> {:error, :unexpected_success}
      {:error, reason} -> {:ok, reason}
    end
  end

  @doc """
  Asserts that compilation fails with an error message matching the given pattern.

  This helper captures compilation warnings/errors from Spark verifiers, which may
  emit DslErrors that get logged as warnings but don't prevent compilation.

  ## Parameters

    * `error_pattern` - Regex pattern to match against error message
    * `dsl_code` - String containing Elixir DSL code

  ## Raises

    * `ExUnit.AssertionError` if no error/warning matches the pattern
  """
  def assert_compile_error(error_pattern, dsl_code) do
    test_process = self()

    # Capture IO and Logger output during compilation to catch Spark verifier
    # failures, which may be emitted as warnings instead of returned errors.
    output =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        log =
          ExUnit.CaptureLog.capture_log(fn ->
            case compile_resource(dsl_code) do
              {:ok, _module} ->
                :ok

              {:error, %Spark.Error.DslError{message: message}} ->
                # Direct error - check if it matches
                if Regex.match?(error_pattern, message) do
                  :ok
                else
                  IO.puts(:stderr, "DslError: #{message}")
                end

              {:error, error} ->
                error_message = Exception.message(error)
                IO.puts(:stderr, "Error: #{error_message}")
            end
          end)

        send(test_process, {:compile_log, log})
      end)

    log =
      receive do
        {:compile_log, log} -> log
      after
        1_000 -> ExUnit.Assertions.flunk("expected compilation log capture")
      end

    output = output <> log

    # Check if the captured output contains the expected error pattern
    unless Regex.match?(error_pattern, output) do
      ExUnit.Assertions.flunk("""
      Expected compilation to emit error matching #{inspect(error_pattern)}

      Captured output:
      #{String.slice(output, 0, 1000)}
      """)
    end
  end
end
