defmodule Altar.AI.Integrations.FlowStone.Telemetry do
  @moduledoc """
  Bridges altar_ai telemetry events to FlowStone's telemetry namespace.

  Attaches handlers that forward `[:altar, :ai, *]` events to
  `[:flowstone, :ai, *]` namespace for unified observability.

  ## Usage

  Call `attach/0` once during application startup:

      def start(_type, _args) do
        Altar.AI.Integrations.FlowStone.Telemetry.attach()
        # ... rest of startup
      end

  ## Events

  The following events are bridged:

    * `[:altar, :ai, :generate, :start]` -> `[:flowstone, :ai, :generate, :start]`
    * `[:altar, :ai, :generate, :stop]` -> `[:flowstone, :ai, :generate, :stop]`
    * `[:altar, :ai, :generate, :exception]` -> `[:flowstone, :ai, :generate, :exception]`
    * `[:altar, :ai, :embed, :start]` -> `[:flowstone, :ai, :embed, :start]`
    * `[:altar, :ai, :embed, :stop]` -> `[:flowstone, :ai, :embed, :stop]`
    * `[:altar, :ai, :embed, :exception]` -> `[:flowstone, :ai, :embed, :exception]`
  """

  require Logger

  @events [
    [:altar, :ai, :generate, :start],
    [:altar, :ai, :generate, :stop],
    [:altar, :ai, :generate, :exception],
    [:altar, :ai, :embed, :start],
    [:altar, :ai, :embed, :stop],
    [:altar, :ai, :embed, :exception]
  ]

  @doc """
  Attach telemetry handlers to bridge altar_ai events to FlowStone namespace.

  This function is idempotent - calling it multiple times will not create
  duplicate handlers.

  Returns `:ok` on success.
  """
  @spec attach() :: :ok
  def attach do
    :telemetry.attach_many(
      "altar-ai-flowstone-bridge",
      @events,
      &handle_event/4,
      nil
    )

    Logger.debug("Altar.AI.Integrations.FlowStone telemetry bridge attached")
    :ok
  end

  @doc """
  Detach the telemetry handlers.

  Useful for testing or if you need to disable the bridge.
  """
  @spec detach() :: :ok | {:error, :not_found}
  def detach do
    :telemetry.detach("altar-ai-flowstone-bridge")
  end

  # Private event handler

  defp handle_event([:altar, :ai | rest], measurements, metadata, _config) do
    :telemetry.execute([:flowstone, :ai | rest], measurements, metadata)
  end
end
