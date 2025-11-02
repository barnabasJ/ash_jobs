defmodule AshJobs.TestDomain do
  @moduledoc """
  Test domain for integration testing.
  """

  use Ash.Domain

  resources do
    resource AshJobs.TestResources.OrderFulfillmentJob
  end
end
