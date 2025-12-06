defmodule Altar.AI.Telemetry do
  @moduledoc """
  Telemetry instrumentation for Altar.AI operations.

  This module provides telemetry events for all AI operations, allowing
  applications to monitor performance, track usage, and debug issues.

  ## Events

  All events are prefixed with `[:altar, :ai]` and include:

  ### Text Generation
    * `[:altar, :ai, :text_gen, :start]` - Text generation started
    * `[:altar, :ai, :text_gen, :stop]` - Text generation completed
    * `[:altar, :ai, :text_gen, :exception]` - Text generation failed

  ### Embeddings
    * `[:altar, :ai, :embed, :start]` - Embedding generation started
    * `[:altar, :ai, :embed, :stop]` - Embedding generation completed
    * `[:altar, :ai, :embed, :exception]` - Embedding generation failed

  ### Classification
    * `[:altar, :ai, :classify, :start]` - Classification started
    * `[:altar, :ai, :classify, :stop]` - Classification completed
    * `[:altar, :ai, :classify, :exception]` - Classification failed

  ### Code Generation
    * `[:altar, :ai, :code_gen, :start]` - Code generation started
    * `[:altar, :ai, :code_gen, :stop]` - Code generation completed
    * `[:altar, :ai, :code_gen, :exception]` - Code generation failed

  ## Event Metadata

  All `:start` events include:
    * `:provider` - AI provider name
    * `:operation` - Operation type
    * `:model` - Model identifier (if available)

  All `:stop` events include:
    * `:provider` - AI provider name
    * `:operation` - Operation type
    * `:tokens` - Token usage (if available)
    * `:duration` - Operation duration in native time units

  All `:exception` events include:
    * `:provider` - AI provider name
    * `:operation` - Operation type
    * `:error` - Error information

  ## Usage

      # Attach a handler
      :telemetry.attach(
        "my-handler",
        [:altar, :ai, :text_gen, :stop],
        &MyModule.handle_event/4,
        nil
      )

      # Use in your code
      Altar.AI.Telemetry.span(:text_gen, %{provider: :gemini}, fn ->
        # Your AI operation
        {:ok, result}
      end)

  """

  require Logger

  @doc """
  Executes a function within a telemetry span.

  Automatically emits `:start`, `:stop`, and `:exception` events.

  ## Parameters

    * `operation` - Operation name (`:text_gen`, `:embed`, `:classify`, `:code_gen`)
    * `metadata` - Event metadata (must include `:provider`)
    * `fun` - Function to execute

  ## Returns

  Returns the result of the function.

  """
  @spec span(atom(), map(), (-> result)) :: result when result: any()
  def span(operation, metadata, fun) do
    start_time = System.monotonic_time()
    event_prefix = [:altar, :ai, operation]

    start_metadata = Map.put(metadata, :operation, operation)

    :telemetry.execute(
      event_prefix ++ [:start],
      %{system_time: System.system_time()},
      start_metadata
    )

    try do
      result = fun.()

      duration = System.monotonic_time() - start_time
      stop_metadata = Map.merge(start_metadata, extract_stop_metadata(result))
      :telemetry.execute(event_prefix ++ [:stop], %{duration: duration}, stop_metadata)

      result
    rescue
      error ->
        duration = System.monotonic_time() - start_time

        exception_metadata =
          start_metadata
          |> Map.put(:error, error)
          |> Map.put(:stacktrace, __STACKTRACE__)

        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: duration},
          exception_metadata
        )

        reraise error, __STACKTRACE__
    end
  end

  @doc """
  Emits a custom event.

  ## Parameters

    * `event` - Event name (list of atoms)
    * `measurements` - Event measurements (map)
    * `metadata` - Event metadata (map)

  """
  @spec emit([atom()], map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute([:altar, :ai | event], measurements, metadata)
  end

  # Private helpers

  defp extract_stop_metadata({:ok, response}) when is_map(response) do
    %{
      tokens: Map.get(response, :tokens),
      model: Map.get(response, :model),
      status: :ok
    }
  end

  defp extract_stop_metadata({:error, _error}) do
    %{status: :error}
  end

  defp extract_stop_metadata(_) do
    %{status: :unknown}
  end
end
