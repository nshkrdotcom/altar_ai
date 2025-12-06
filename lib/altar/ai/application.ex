defmodule Altar.AI.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Mock adapter agent for testing
      {Altar.AI.Adapters.Mock, []}
    ]

    opts = [strategy: :one_for_one, name: Altar.AI.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
