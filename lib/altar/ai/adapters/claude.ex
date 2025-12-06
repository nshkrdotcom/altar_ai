defmodule Altar.AI.Adapters.Claude do
  @moduledoc """
  Claude adapter for Altar.AI.

  This adapter wraps the `claude_agent_sdk` package to provide TextGen
  capabilities through Anthropic's Claude API.

  ## Configuration

      config :altar_ai,
        adapters: %{
          claude: [
            api_key: {:system, "ANTHROPIC_API_KEY"},
            model: "claude-3-opus-20240229"
          ]
        }

  ## Examples

      iex> Altar.AI.Adapters.Claude.generate("Hello", model: "claude-3-opus-20240229")
      {:ok, %{content: "Hi there!", model: "claude-3-opus-20240229", ...}}

  """

  @behaviour Altar.AI.Behaviours.TextGen

  alias Altar.AI.{Config, Error, Response}

  @impl true
  def generate(prompt, opts \\ []) do
    if claude_available?() do
      generate_with_claude(prompt, opts)
    else
      {:error,
       Error.new(
         :not_found,
         "Claude Agent SDK not available. Add {:claude_agent_sdk, \"~> 0.1.0\"} to your deps.",
         :claude
       )}
    end
  end

  @impl true
  def stream(prompt, opts \\ []) do
    if claude_available?() do
      stream_with_claude(prompt, opts)
    else
      {:error,
       Error.new(
         :not_found,
         "Claude Agent SDK not available. Add {:claude_agent_sdk, \"~> 0.1.0\"} to your deps.",
         :claude
       )}
    end
  end

  # Private implementation

  defp claude_available? do
    Code.ensure_loaded?(ClaudeAgentSDK)
  end

  defp generate_with_claude(prompt, opts) do
    config = Config.get_adapter_config(:claude)
    model = Keyword.get(opts, :model, Keyword.get(config, :model, "claude-3-opus-20240229"))

    request_opts =
      opts
      |> Keyword.take([:temperature, :max_tokens, :top_p, :system])
      |> Keyword.put(:model, model)
      |> Keyword.put(:api_key, Keyword.get(config, :api_key))

    case ClaudeAgentSDK.query(prompt, request_opts) do
      {:ok, response} ->
        {:ok, normalize_generate_response(response, model)}

      {:error, error} ->
        {:error, normalize_error(error)}
    end
  end

  defp stream_with_claude(prompt, opts) do
    config = Config.get_adapter_config(:claude)
    model = Keyword.get(opts, :model, Keyword.get(config, :model, "claude-3-opus-20240229"))

    request_opts =
      opts
      |> Keyword.take([:temperature, :max_tokens, :top_p, :system])
      |> Keyword.put(:model, model)
      |> Keyword.put(:api_key, Keyword.get(config, :api_key))
      |> Keyword.put(:stream, true)

    case ClaudeAgentSDK.query(prompt, request_opts) do
      {:ok, stream} when is_function(stream) or is_struct(stream, Stream) ->
        normalized_stream =
          Stream.map(stream, fn chunk ->
            %{
              content: Response.extract_content(chunk),
              delta: true,
              finish_reason: Map.get(chunk, :finish_reason)
            }
          end)

        {:ok, normalized_stream}

      {:ok, response} ->
        # Non-streaming response, convert to single-item stream
        stream =
          Stream.map([response], fn chunk ->
            %{
              content: Response.extract_content(chunk),
              delta: false,
              finish_reason: :stop
            }
          end)

        {:ok, stream}

      {:error, error} ->
        {:error, normalize_error(error)}
    end
  end

  defp normalize_generate_response(response, model) do
    %{
      content: Response.extract_content(response),
      model: model,
      tokens: Response.normalize_tokens(Map.get(response, :usage, %{})),
      finish_reason: Response.normalize_finish_reason(Map.get(response, :stop_reason)),
      metadata: Response.extract_metadata(response)
    }
  end

  defp normalize_error(error) when is_binary(error) do
    Error.new(:api_error, error, :claude)
  end

  defp normalize_error(%{message: message, type: type}) do
    error_type = map_error_type(type)
    Error.new(error_type, message, :claude, retryable?: Error.retryable_by_default?(error_type))
  end

  defp normalize_error(%{message: message}) do
    Error.new(:api_error, message, :claude)
  end

  defp normalize_error(error) do
    Error.new(:api_error, inspect(error), :claude)
  end

  defp map_error_type("rate_limit_error"), do: :rate_limit
  defp map_error_type("timeout"), do: :timeout
  defp map_error_type("api_error"), do: :api_error
  defp map_error_type("invalid_request_error"), do: :validation_error
  defp map_error_type("permission_error"), do: :permission_denied
  defp map_error_type(_), do: :api_error
end
