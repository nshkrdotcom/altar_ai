defmodule Altar.AI.Integrations.Command do
  @moduledoc """
  Command integration for Altar.AI telemetry and cost tracking.

  Attaches to Altar.AI telemetry events and records costs in Command.Costs.
  This module bridges the AI layer with Command's cost tracking system.

  ## Usage

  Call during Command application startup:

      def start(_type, _args) do
        Altar.AI.Integrations.Command.attach_telemetry()

        children = [
          # ... your supervisors
        ]

        opts = [strategy: :one_for_one, name: Command.Supervisor]
        Supervisor.start_link(children, opts)
      end

  ## Telemetry Events

  This module listens for:
    * `[:altar, :ai, :text_gen, :stop]` - Text generation completed
    * `[:altar, :ai, :embed, :stop]` - Embedding generation completed
    * `[:altar, :ai, :code_gen, :stop]` - Code generation completed

  When a `command_session_id` is present in event metadata, costs are
  recorded to `Command.Costs.record_ai_operation/1`.

  ## Session Tracking

  To enable cost tracking, include session metadata when calling Altar.AI:

      Altar.AI.generate(adapter, prompt,
        command_session_id: session_id,
        command_workflow_id: workflow_id
      )

  ## Cost Calculation

  Costs are calculated based on model pricing tables. The module includes
  pricing for common models from OpenAI, Anthropic, and Google.
  """

  require Logger

  @handler_id "altar-ai-command-integration"

  @doc """
  Attach telemetry handlers for Command cost tracking.

  Idempotent - calling multiple times has no effect after the first call.

  ## Examples

      iex> Altar.AI.Integrations.Command.attach_telemetry()
      :ok

      # Calling again is safe
      iex> Altar.AI.Integrations.Command.attach_telemetry()
      :ok
  """
  @spec attach_telemetry() :: :ok
  def attach_telemetry do
    events = [
      [:altar, :ai, :text_gen, :stop],
      [:altar, :ai, :embed, :stop],
      [:altar, :ai, :code_gen, :stop],
      [:altar, :ai, :generate, :stop],
      [:altar, :ai, :classify, :stop]
    ]

    # Detach first to ensure idempotency
    _ = :telemetry.detach(@handler_id)

    :telemetry.attach_many(
      @handler_id,
      events,
      &handle_event/4,
      nil
    )

    :ok
  end

  @doc """
  Detach telemetry handlers.

  ## Examples

      iex> Altar.AI.Integrations.Command.detach_telemetry()
      :ok
  """
  @spec detach_telemetry() :: :ok
  def detach_telemetry do
    _ = :telemetry.detach(@handler_id)
    :ok
  end

  @doc """
  Check if telemetry handlers are attached.

  ## Examples

      iex> Altar.AI.Integrations.Command.attached?()
      true
  """
  @spec attached?() :: boolean()
  def attached? do
    :telemetry.list_handlers([:altar, :ai, :text_gen, :stop])
    |> Enum.any?(fn handler -> handler.id == @handler_id end)
  end

  @doc false
  def handle_event([:altar, :ai, operation, :stop], measurements, metadata, _config) do
    session_id = Map.get(metadata, :command_session_id)

    if session_id do
      attrs = build_cost_attrs(operation, measurements, metadata, session_id)
      record_cost(attrs)
    end

    :ok
  end

  defp build_cost_attrs(operation, measurements, metadata, session_id) do
    model = Map.get(metadata, :model)
    tokens = Map.get(metadata, :tokens) || %{}
    duration = Map.get(measurements, :duration)

    tokens_in = extract_input_tokens(tokens)
    tokens_out = extract_output_tokens(tokens)
    cost_usd = calculate_cost(model, tokens_in, tokens_out)

    %{
      session_id: session_id,
      workflow_id: Map.get(metadata, :command_workflow_id),
      operation: normalize_operation(operation),
      model: normalize_model(model),
      provider: normalize_provider(Map.get(metadata, :provider)),
      tokens_in: tokens_in,
      tokens_out: tokens_out,
      cost_usd: cost_usd,
      duration_ms: native_to_ms(duration),
      metadata: extract_extra_metadata(metadata)
    }
  end

  defp normalize_operation(:text_gen), do: :generate
  defp normalize_operation(:code_gen), do: :code_generate
  defp normalize_operation(op), do: op

  defp normalize_provider(nil), do: nil
  defp normalize_provider(provider) when is_binary(provider), do: provider
  defp normalize_provider(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp normalize_provider(provider), do: to_string(provider)

  defp normalize_model(nil), do: nil
  defp normalize_model(model) when is_binary(model), do: model

  defp extract_input_tokens(%{prompt: prompt}), do: prompt
  defp extract_input_tokens(%{input: input}), do: input
  defp extract_input_tokens(%{input_tokens: input}), do: input
  defp extract_input_tokens(_), do: 0

  defp extract_output_tokens(%{completion: completion}), do: completion
  defp extract_output_tokens(%{output: output}), do: output
  defp extract_output_tokens(%{output_tokens: output}), do: output
  defp extract_output_tokens(_), do: 0

  defp extract_extra_metadata(metadata) do
    metadata
    |> Map.take([:profile, :finish_reason, :request_id])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Calculate estimated cost in USD for an AI operation.

  ## Parameters

    * `model` - Model identifier string
    * `tokens_in` - Number of input/prompt tokens
    * `tokens_out` - Number of output/completion tokens

  ## Examples

      iex> Altar.AI.Integrations.Command.calculate_cost("gpt-4o", 1000, 500)
      0.0125

      iex> Altar.AI.Integrations.Command.calculate_cost("unknown-model", 1000, 500)
      nil
  """
  @spec calculate_cost(String.t() | nil, non_neg_integer(), non_neg_integer()) :: float() | nil
  def calculate_cost(nil, _tokens_in, _tokens_out), do: nil
  def calculate_cost(_model, 0, 0), do: 0.0

  def calculate_cost(model, tokens_in, tokens_out) when is_binary(model) do
    case model_pricing(model) do
      {input_price, output_price} ->
        (tokens_in * input_price + tokens_out * output_price) / 1_000_000

      nil ->
        nil
    end
  end

  # Pricing per million tokens (approximate, as of early 2026)
  # OpenAI models
  defp model_pricing("gpt-4o"), do: {5.0, 15.0}
  defp model_pricing("gpt-4o-mini"), do: {0.15, 0.60}
  defp model_pricing("gpt-4-turbo" <> _), do: {10.0, 30.0}
  defp model_pricing("gpt-4" <> _), do: {30.0, 60.0}
  defp model_pricing("gpt-3.5-turbo" <> _), do: {0.50, 1.50}
  defp model_pricing("o1" <> _), do: {15.0, 60.0}
  defp model_pricing("o3-mini" <> _), do: {1.10, 4.40}

  # Anthropic models
  defp model_pricing("claude-3-opus" <> _), do: {15.0, 75.0}
  defp model_pricing("claude-3-sonnet" <> _), do: {3.0, 15.0}
  defp model_pricing("claude-3-haiku" <> _), do: {0.25, 1.25}
  defp model_pricing("claude-sonnet-4" <> _), do: {3.0, 15.0}
  defp model_pricing("claude-opus-4" <> _), do: {15.0, 75.0}

  # Google Gemini models
  defp model_pricing("gemini-pro"), do: {0.50, 1.50}
  defp model_pricing("gemini-1.5-pro" <> _), do: {3.50, 10.50}
  defp model_pricing("gemini-1.5-flash" <> _), do: {0.075, 0.30}
  defp model_pricing("gemini-2.0-flash" <> _), do: {0.10, 0.40}

  # Embedding models (output price is typically 0)
  defp model_pricing("text-embedding-004"), do: {0.025, 0.0}
  defp model_pricing("text-embedding-3-small"), do: {0.02, 0.0}
  defp model_pricing("text-embedding-3-large"), do: {0.13, 0.0}
  defp model_pricing("text-embedding-ada" <> _), do: {0.10, 0.0}

  defp model_pricing(_), do: nil

  defp record_cost(attrs) do
    # Check if Command.Costs module is available
    if command_costs_available?() do
      command_module = Module.concat(Command, Costs)

      try do
        command_module.record_ai_operation(attrs)
      rescue
        error ->
          Logger.warning(
            "Failed to record AI cost to Command.Costs: #{inspect(error)} " <>
              "attrs=#{inspect(attrs)}"
          )
      end
    else
      Logger.debug(
        "Command.Costs not available, skipping cost recording " <>
          "attrs=#{inspect(Map.take(attrs, [:operation, :model, :cost_usd]))}"
      )
    end
  end

  defp command_costs_available? do
    command_module = Module.concat(Command, Costs)

    Code.ensure_loaded?(command_module) and
      function_exported?(command_module, :record_ai_operation, 1)
  end

  defp native_to_ms(duration) when is_integer(duration) do
    System.convert_time_unit(duration, :native, :millisecond)
  end

  defp native_to_ms(_), do: nil
end
