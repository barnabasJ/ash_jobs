defmodule AshJobs.TestDomain do
  @moduledoc """
  Test domain for integration testing.
  """

  use Ash.Domain

  resources do
    resource AshJobs.TestResources.OrderFulfillmentJob
    resource AshJobs.TestResources.SimpleWorkflow
    resource AshJobs.TestResources.BranchingWorkflow
    resource AshJobs.TestResources.ManualWorkflow
    resource AshJobs.TestResources.LongRunningWorkflow
    resource AshJobs.TestResources.SingleStepWorkflow
    resource AshJobs.TestResources.MultiTerminalWorkflow
    resource AshJobs.TestResources.CustomStateWorkflow
    resource AshJobs.TestResources.DagRun
    resource AshJobs.TestResources.DagJob
    resource AshJobs.TestResources.DagNeed
    resource AshJobs.TestResources.PollingDagJob
    resource AshJobs.TestResources.PollingDagNeed
    resource AshJobs.TestResources.StaticBranchWorkflow
    resource AshJobs.TestResources.StaticBranchRun
    resource AshJobs.TestResources.DynamicRequireNRun
  end
end
