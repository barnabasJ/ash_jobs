defmodule AshJobs do
  @moduledoc """
  AshJobs - Declarative workflow DSL for Ash Framework.

  AshJobs dramatically simplifies background job workflows by providing a declarative DSL
  that integrates ash_state_machine and ash_oban, reducing boilerplate by ~75%.

  ## Usage

  Add AshJobs as an extension to your Ash resource alongside AshStateMachine and AshOban:

      defmodule MyApp.Orders.FulfillmentJob do
        use Ash.Resource,
          extensions: [AshJobs, AshStateMachine, AshOban]

        workflow do
          step :load_order do
            action :load_full_order
            on_success :validate_inventory
            on_error :handle_load_error
            queue :order_processing
          end

          step :validate_inventory do
            action :check_inventory
            on_success :create_shipment
            on_error :notify_inventory_error
            queue :inventory_processing
          end

          step :create_shipment do
            action :create_shipment
            on_success :completed
            queue :shipping_processing
          end
        end

        # ... attributes, actions, etc.
      end

  ## What Gets Generated

  AshJobs automatically generates:

  1. **State Machine DSL** (if not already defined) - One state per step + terminal states
  2. **Oban Triggers** (if not already defined) - Automatic job scheduling per step
  3. **Error Handler Actions** - Simple actions that transition to error states
  4. **Verification & Injection** - Missing changes injected with educational warnings

  ## Architecture

  - **Transformers**: Generate missing DSL (state_machine, oban, error actions)
  - **Verifiers**: Validate workflow structure and inject missing changes with warnings
  - **Direct Integration**: Uses ash_state_machine and ash_oban directly (no adapter layers)

  See the documentation for `AshJobs.Dsl.Sections.workflow/0` for complete DSL reference.
  """

  alias AshJobs.Dsl.Sections

  use Spark.Dsl.Extension,
    sections: [Sections.workflow()],
    transformers: [
      # Generate error handler actions first (they're simple state transitions)
      AshJobs.Transformers.GenerateErrorActions,
      # Inject Change module into workflow actions for routing
      AshJobs.Transformers.BuildWorkflow,
      # Then integrate with ash_state_machine (uses generated error actions)
      AshJobs.Transformers.IntegrateStateMachine,
      # Finally integrate with ash_oban (references state machine states)
      AshJobs.Transformers.IntegrateOban
    ],
    verifiers: [
      # Verify workflow structure and inject missing changes with warnings
      AshJobs.Verifiers.ValidateWorkflow
    ]
end
