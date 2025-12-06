defmodule Altar.AI.Adapters.Claude do
  @moduledoc """
  Claude adapter wrapping claude_agent_sdk.

  Provides protocol implementations for Claude AI capabilities including
  text generation.
  """

  defstruct opts: []

  @type t :: %__MODULE__{opts: keyword()}

  def new(opts \\ []), do: %__MODULE__{opts: opts}

  @claude_available Code.ensure_loaded?(ClaudeAgentSDK)
  def available?, do: @claude_available
end

if Code.ensure_loaded?(ClaudeAgentSDK) do
  defimpl Altar.AI.Generator, for: Altar.AI.Adapters.Claude do
    alias Altar.AI.{Response, Error, Telemetry}

    def generate(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)

      Telemetry.span(:generate, %{provider: :claude}, fn ->
        model = merged_opts[:model] || "claude-3-opus-20240229"

        sdk_opts = build_sdk_options(merged_opts)

        content =
          ClaudeAgentSDK.query(prompt, sdk_opts)
          |> Enum.reduce("", fn msg, acc ->
            case msg do
              %{type: :assistant, content: text} when is_binary(text) -> acc <> text
              %{content: text} when is_binary(text) -> acc <> text
              _ -> acc
            end
          end)

        {:ok,
         %Response{
           content: content,
           model: model,
           provider: :claude,
           finish_reason: :stop
         }}
      end)
    end

    def stream(_adapter, _prompt, _opts) do
      {:error, Error.new(:unsupported, "Claude streaming not yet implemented", provider: :claude)}
    end

    defp build_sdk_options(opts) do
      opts
      |> Keyword.take([:model, :api_key, :temperature, :max_tokens, :top_p, :system])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    end
  end

  # Claude doesn't support embeddings - no Embedder impl
end
