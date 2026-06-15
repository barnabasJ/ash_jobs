defmodule AshJobs.Dsl.Sections do
  @moduledoc """
  DSL section definitions for AshJobs workflows.

  Defines the top-level `workflow` section that contains workflow configuration
  and step definitions.
  """

  alias AshJobs.Dsl.Entities.{Step, ParallelStep, Branch}

  @doc """
  Defines the workflow section.

  A resource can have one workflow, which contains a series of steps that execute sequentially.

  ## Options

  - `:state_attribute` (atom) - Attribute to use for tracking workflow state (defaults to :state)
  - `:triggers` (boolean) - Whether to generate Oban triggers (defaults to false)

  ## Examples

      # Root workflow with triggers enabled
      workflow do
        triggers true
        state_attribute :workflow_state  # Optional override

        step :load_order do
          action :load_full_order
          on_success :validate_inventory
          on_error :handle_load_error
        end

        step :validate_inventory do
          action :check_inventory
          on_success :create_shipment
          on_error :notify_inventory_error
        end
      end

      # Child workflow (used in parallel_step) - no triggers needed
      workflow do
        step :process do
          action :process
          on_success :completed
        end
      end
  """
  def workflow do
    %Spark.Dsl.Section{
      name: :workflow,
      top_level?: false,
      schema: [
        state_attribute: [
          type: :atom,
          default: :state,
          doc: "Attribute to use for tracking workflow state"
        ],
        triggers: [
          type: :boolean,
          default: false,
          doc: """
          Whether to generate Oban triggers for this workflow.

          Defaults to false since most workflows are child resources used in parallel regions.
          Set to true for "root" workflows that should be triggered by Oban.

          When enabled, generates triggers for:
          - Regular steps (filtered by step state)
          - Wrapper actions for parallel_steps (e.g., :payment_process)
          """
        ],
        read_action: [
          type: :atom,
          required: false,
          doc: """
          Read action the generated Oban trigger schedulers use to find records to advance.

          Applied as `read_action` on every generated trigger (regular and parallel
          wrapper). Defaults to the resource's primary read action when unset.

          The main reason to set this is multitenancy: a multitenant resource whose
          primary read enforces a tenant cannot be scanned by the scheduler (which runs
          tenant-lessly). Point this at a `multitenancy :allow_global` read action so the
          scheduler scans across tenants, and set `use_tenant_from_record? true` in the
          resource's `oban` section so each worker still runs with its record's tenant.
          """
        ],
        needs: [
          type: :atom,
          required: false,
          doc:
            "Relationship on workflow rows that lists prerequisite rows which must reach success before this row can run."
        ],
        push_dependents: [
          type: :boolean,
          default: true,
          doc:
            "Whether a row reaching success should immediately push dependents whose needs are now satisfied."
        ]
      ],
      entities: [
        %Spark.Dsl.Entity{
          name: :step,
          target: Step,
          args: [:name],
          schema: Step.schema(),
          imports: [Ash.Expr],
          describe: "Defines a step in the workflow"
        },
        %Spark.Dsl.Entity{
          name: :parallel_step,
          target: ParallelStep,
          args: [:name],
          schema: ParallelStep.schema(),
          entities: [
            branches: [
              %Spark.Dsl.Entity{
                name: :branch,
                target: Branch,
                args: Branch.args(),
                schema: Branch.schema(),
                describe: "Defines a branch workflow resource"
              }
            ]
          ],
          describe: "Defines a parallel step coordinating multiple concurrent branches"
        }
      ],
      describe: """
      Defines a sequential workflow with explicit step routing.

      One workflow per resource, aligned with ash_state_machine's one-state-machine-per-resource design.
      """
    }
  end
end
