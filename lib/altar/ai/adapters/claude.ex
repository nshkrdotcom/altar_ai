defmodule Altar.AI.Adapters.Claude do
  @moduledoc """
  Claude adapter wrapping claude_agent_sdk.

  Provides protocol implementations for Anthropic Claude AI capabilities including
  text generation and streaming.

  This adapter uses the `claude_agent_sdk` hex package. The SDK must be available
  at compile time for protocol implementations to be defined.

  ## Features

  - Text generation with message history
  - Streaming via ClaudeAgentSDK.Streaming
  - System prompt support
  - Token usage tracking

  ## Models

  Common models include:
  - "claude-sonnet-4-20250514" (Claude 4 Sonnet)
  - "claude-opus-4-20250514" (Claude 4 Opus)
  - "claude-3-haiku-20240307" (Claude 3 Haiku)

  ## Example

      # Create adapter with default options
      adapter = Altar.AI.Adapters.Claude.new()

      # Create with custom model
      adapter = Altar.AI.Adapters.Claude.new(model: "claude-sonnet-4-20250514")

      # Generate text
      {:ok, response} = Altar.AI.generate(adapter, "What is Elixir?")
  """

  require Logger

  defstruct opts: []

  @type t :: %__MODULE__{opts: keyword()}

  @default_models [
    "claude-sonnet-4-20250514",
    "claude-opus-4-20250514",
    "claude-3-haiku-20240307"
  ]

  @doc """
  Create a new Claude adapter.

  ## Options

    - `:api_key` - Anthropic API key (defaults to ANTHROPIC_API_KEY env var via SDK)
    - `:model` - Default model to use (e.g., "claude-sonnet-4-20250514")
    - `:temperature` - Sampling temperature
    - `:max_tokens` - Maximum tokens in response
    - `:system` - System prompt for the model
    - `:max_thinking_tokens` - Maximum thinking tokens for reasoning models
    - Other options passed through to claude_agent_sdk

  ## Examples

      iex> Altar.AI.Adapters.Claude.new(model: "claude-sonnet-4-20250514")
      %Altar.AI.Adapters.Claude{opts: [model: "claude-sonnet-4-20250514"]}

      iex> Altar.AI.Adapters.Claude.new(model: "claude-3-opus-20240229", temperature: 0.7)
      %Altar.AI.Adapters.Claude{opts: [model: "claude-3-opus-20240229", temperature: 0.7]}
  """
  def new(opts \\ []), do: %__MODULE__{opts: opts}

  @doc """
  Check if the Claude SDK (claude_agent_sdk) is available.

  Returns `true` if the claude_agent_sdk library is loaded and available.
  """
  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(ClaudeAgentSDK)

  @doc """
  List supported models.

  Returns a list of model identifiers that can be used for text generation.
  If the SDK provides a supported_models function, uses that; otherwise returns defaults.
  """
  @spec supported_models() :: [String.t()]
  def supported_models do
    if available?() do
      sdk = sdk_module()

      if function_exported?(sdk, :supported_models, 0) do
        sdk.supported_models()
      else
        @default_models
      end
    else
      @default_models
    end
  end

  @doc """
  Get model info for a specific model.

  Returns a map with context window, max output, and tool support info.
  """
  @spec model_info(String.t()) :: map()
  def model_info(model) do
    if available?() do
      sdk = sdk_module()
      fetch_model_info(sdk, model)
    else
      default_model_info()
    end
  end

  defp fetch_model_info(sdk, model) do
    if function_exported?(sdk, :model_info, 1) do
      normalize_model_info(sdk.model_info(model))
    else
      default_model_info()
    end
  end

  defp normalize_model_info(%{} = info), do: info
  defp normalize_model_info({:ok, info}) when is_map(info), do: info
  defp normalize_model_info(_), do: default_model_info()

  defp default_model_info do
    %{
      context_window: 200_000,
      max_output: 4096,
      supports_tools: true
    }
  end

  defp sdk_module do
    Application.get_env(:altar_ai, :claude_sdk, ClaudeAgentSDK)
  end
end

if Code.ensure_loaded?(ClaudeAgentSDK) do
  defimpl Altar.AI.Generator, for: Altar.AI.Adapters.Claude do
    alias Altar.AI.{Error, Response, Telemetry}
    alias ClaudeAgentSDK.{ContentExtractor, Message, Options}

    require Logger

    def generate(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)
      model = merged_opts[:model] || "claude-sonnet-4-20250514"
      sdk = sdk_module()

      Telemetry.span(:text_gen, %{provider: :claude, model: model}, fn ->
        cond do
          function_exported?(sdk, :complete, 2) ->
            complete_via_sdk(sdk, prompt, merged_opts, model)

          function_exported?(sdk, :query, 2) ->
            complete_via_query(sdk, prompt, merged_opts, model)

          true ->
            {:error, Error.new(:unsupported, "No supported completion method", provider: :claude)}
        end
      end)
    end

    def stream(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)
      model = merged_opts[:model] || "claude-sonnet-4-20250514"
      sdk = sdk_module()

      Telemetry.span(:stream, %{provider: :claude, model: model}, fn ->
        cond do
          function_exported?(sdk, :stream, 2) or function_exported?(sdk, :stream, 3) ->
            stream_via_sdk(sdk, prompt, merged_opts, model)

          sdk == ClaudeAgentSDK and
              function_exported?(ClaudeAgentSDK.Streaming, :start_session, 1) ->
            stream_via_streaming(prompt, merged_opts, model)

          function_exported?(sdk, :query, 2) ->
            # Fall back to non-streaming and simulate
            stream_from_complete(sdk, prompt, merged_opts, model)

          true ->
            {:error, Error.new(:unsupported, "Streaming not supported", provider: :claude)}
        end
      end)
    end

    defp complete_via_sdk(sdk, prompt, opts, model) do
      sdk_opts = build_sdk_options(opts, model)
      messages = convert_prompt_to_messages(prompt)

      case sdk.complete(messages, sdk_opts) do
        {:ok, response} ->
          {:ok, normalize_response(response, model)}

        {:error, reason} ->
          Logger.error("Claude completion failed: #{inspect(reason)}")
          {:error, Error.new(:api_error, inspect(reason), provider: :claude)}
      end
    end

    defp complete_via_query(sdk, prompt, opts, model) do
      options = build_query_options(opts, model)

      response_messages =
        try do
          sdk.query(prompt, options) |> Enum.to_list()
        rescue
          error ->
            Logger.error("Claude query failed: #{inspect(error)}")
            {:error, error}
        end

      case response_messages do
        {:error, error} ->
          {:error, Error.new(:api_error, inspect(error), provider: :claude)}

        messages ->
          extract_query_response(messages, options, model)
      end
    end

    defp stream_via_sdk(sdk, prompt, opts, model) do
      sdk_opts = build_sdk_options(opts, model)
      messages = convert_prompt_to_messages(prompt)

      cond do
        function_exported?(sdk, :stream, 2) ->
          case sdk.stream(messages, sdk_opts) do
            {:ok, stream} -> {:ok, normalize_stream(stream)}
            {:error, _} = error -> error
            stream -> {:ok, normalize_stream(stream)}
          end

        function_exported?(sdk, :stream, 3) ->
          {:ok, callback_stream(sdk, messages, sdk_opts)}

        true ->
          {:error, Error.new(:unsupported, "Stream not supported", provider: :claude)}
      end
    end

    defp stream_via_streaming(prompt, opts, model) do
      options = build_query_options(opts, model)

      case ClaudeAgentSDK.Streaming.start_session(options) do
        {:ok, session} ->
          stream = streaming_session_stream(session, prompt)
          {:ok, stream}

        {:error, reason} ->
          {:error, Error.new(:api_error, inspect(reason), provider: :claude)}
      end
    end

    defp stream_from_complete(sdk, prompt, opts, model) do
      case complete_via_query(sdk, prompt, opts, model) do
        {:ok, response} ->
          {:ok, response_stream(response.content, response.finish_reason)}

        {:error, _} = error ->
          error
      end
    end

    defp streaming_session_stream(session, prompt) do
      Stream.resource(
        fn -> start_session_stream(session, prompt) end,
        &continue_session_stream/1,
        &close_session_stream/1
      )
    end

    defp start_session_stream(session, prompt) do
      parent = self()
      ref = make_ref()

      _pid =
        spawn(fn ->
          ClaudeAgentSDK.Streaming.send_message(session, prompt)
          |> Enum.each(fn event -> send(parent, {:event, ref, event}) end)

          send(parent, {:done, ref})
        end)

      %{session: session, ref: ref, done: false}
    end

    defp continue_session_stream(%{done: true} = state), do: {:halt, state}

    defp continue_session_stream(%{ref: ref} = state) do
      receive do
        {:event, ^ref, %{type: :text_delta, text: text}} ->
          {[%{delta: text, finish_reason: nil}], state}

        {:event, ^ref, %{type: :message_stop}} ->
          {[%{delta: "", finish_reason: :stop}], %{state | done: true}}

        {:event, ^ref, %{type: :error, error: reason}} ->
          {:halt, {:error, reason}}

        {:done, ^ref} ->
          {:halt, %{state | done: true}}
      after
        30_000 ->
          {:halt, {:error, :timeout}}
      end
    end

    defp close_session_stream(%{session: session}) do
      _ = ClaudeAgentSDK.Streaming.close_session(session)
      :ok
    end

    defp close_session_stream(_), do: :ok

    defp build_sdk_options(opts, model) do
      opts
      |> Keyword.take([:api_key, :temperature, :max_tokens, :top_p, :system])
      |> Keyword.put(:model, model)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    end

    defp build_query_options(opts, model) do
      system_prompt = opts[:system] || opts[:system_prompt]
      max_thinking_tokens = opts[:max_thinking_tokens]

      %Options{}
      |> maybe_put_struct(:model, model)
      |> maybe_put_struct(:system_prompt, system_prompt)
      |> maybe_put_struct(:output_format, :json)
      |> maybe_put_struct(:max_turns, 1)
      |> maybe_put_struct(:max_thinking_tokens, max_thinking_tokens)
    end

    defp maybe_put_struct(struct, _key, nil), do: struct
    defp maybe_put_struct(struct, key, value), do: Map.put(struct, key, value)

    defp convert_prompt_to_messages(prompt) when is_binary(prompt) do
      [%{role: "user", content: prompt}]
    end

    defp convert_prompt_to_messages(messages) when is_list(messages) do
      Enum.map(messages, fn
        %{role: role, content: content} -> %{role: to_string(role), content: content}
        %{"role" => role, "content" => content} -> %{role: role, content: content}
        msg -> msg
      end)
    end

    defp extract_query_response(messages, %Options{} = options, model) do
      case find_assistant_error(messages) do
        {:error, reason} ->
          {:error, Error.new(:api_error, reason, provider: :claude)}

        :ok ->
          result_message = Enum.find(messages, &(&1.type == :result))

          content = extract_assistant_content(messages, result_message)
          usage = normalize_usage(result_message)
          finish_reason = extract_finish_reason(result_message)
          actual_model = extract_model(messages, result_message, options, model)

          {:ok,
           %Response{
             content: content,
             model: actual_model,
             provider: :claude,
             finish_reason: finish_reason,
             tokens: usage
           }}
      end
    end

    defp find_assistant_error(messages) do
      case Enum.find(messages, &assistant_error?/1) do
        %Message{data: %{error: error}} when not is_nil(error) ->
          {:error, error}

        _ ->
          case Enum.find(messages, &result_error?/1) do
            %Message{data: %{error: error}} when is_binary(error) -> {:error, error}
            _ -> :ok
          end
      end
    end

    defp assistant_error?(%Message{type: :assistant, data: %{error: error}})
         when not is_nil(error),
         do: true

    defp assistant_error?(_), do: false

    defp result_error?(%Message{type: :result, subtype: subtype})
         when subtype in [:error_max_turns, :error_during_execution],
         do: true

    defp result_error?(_), do: false

    defp extract_assistant_content(messages, result_message) do
      assistant_texts =
        messages
        |> Enum.filter(&(&1.type == :assistant))
        |> Enum.map(&ContentExtractor.extract_text/1)
        |> Enum.reject(&blank?/1)

      case assistant_texts do
        [] ->
          case result_message do
            %Message{} -> ContentExtractor.extract_text(result_message) || ""
            _ -> ""
          end

        _ ->
          Enum.join(assistant_texts, "\n")
      end
    end

    defp extract_model(messages, _result_message, %Options{}, default) do
      case Enum.find(messages, &(&1.type == :system)) do
        %Message{type: :system, data: %{model: model}} when is_binary(model) and model != "" ->
          model

        _ ->
          default
      end
    end

    defp extract_finish_reason(%Message{type: :result, subtype: :success}), do: :stop
    defp extract_finish_reason(%Message{type: :result, subtype: :error_max_turns}), do: :length
    defp extract_finish_reason(_), do: :stop

    defp normalize_usage(%Message{type: :result, data: %{usage: usage}}) do
      normalize_usage_map(usage)
    end

    defp normalize_usage(_), do: %{prompt: 0, completion: 0, total: 0}

    defp normalize_usage_map(usage) when is_map(usage) do
      input =
        Map.get(usage, :input_tokens) ||
          Map.get(usage, "input_tokens") ||
          Map.get(usage, :prompt_tokens) ||
          0

      output =
        Map.get(usage, :output_tokens) ||
          Map.get(usage, "output_tokens") ||
          Map.get(usage, :completion_tokens) ||
          0

      %{prompt: input, completion: output, total: input + output}
    end

    defp normalize_usage_map(_), do: %{prompt: 0, completion: 0, total: 0}

    defp normalize_response(response, model) do
      %Response{
        content: response_content(response),
        model: response_model(response) || model,
        provider: :claude,
        finish_reason: normalize_finish_reason_value(response_finish_reason(response)),
        tokens: normalize_usage_map(response_usage(response))
      }
    end

    defp response_content(response) when is_map(response) do
      Map.get(response, :content) || Map.get(response, "content") || ""
    end

    defp response_model(response) when is_map(response) do
      Map.get(response, :model) || Map.get(response, "model")
    end

    defp response_usage(response) when is_map(response) do
      Map.get(response, :usage) || Map.get(response, "usage") || %{}
    end

    defp response_finish_reason(response) when is_map(response) do
      Map.get(response, :finish_reason) ||
        Map.get(response, "finish_reason") ||
        Map.get(response, :stop_reason) ||
        Map.get(response, "stop_reason")
    end

    defp normalize_finish_reason_value(:stop), do: :stop
    defp normalize_finish_reason_value(:length), do: :length
    defp normalize_finish_reason_value(:tool_use), do: :tool_use
    defp normalize_finish_reason_value("stop"), do: :stop
    defp normalize_finish_reason_value("length"), do: :length
    defp normalize_finish_reason_value("tool_use"), do: :tool_use
    defp normalize_finish_reason_value(other) when is_atom(other), do: other
    defp normalize_finish_reason_value(_), do: :stop

    defp normalize_stream(stream) do
      Stream.map(stream, fn chunk ->
        case chunk do
          %{delta: _} = existing -> existing
          %{content: delta} -> %{delta: delta, finish_reason: nil}
          delta when is_binary(delta) -> %{delta: delta, finish_reason: nil}
          _ -> %{delta: "", finish_reason: nil}
        end
      end)
    end

    defp callback_stream(sdk, messages, sdk_opts) do
      Stream.resource(
        fn -> start_callback_streaming(sdk, messages, sdk_opts) end,
        &continue_callback_streaming/1,
        fn _ -> :ok end
      )
    end

    defp start_callback_streaming(sdk, messages, sdk_opts) do
      parent = self()
      ref = make_ref()

      _pid =
        spawn(fn ->
          result =
            sdk.stream(
              messages,
              fn chunk ->
                send(parent, {:chunk, ref, chunk})
              end,
              sdk_opts
            )

          send(parent, {:done, ref, result})
        end)

      {:streaming, ref}
    end

    defp continue_callback_streaming({:streaming, ref}) do
      receive do
        {:chunk, ^ref, chunk} ->
          {[%{delta: normalize_stream_chunk(chunk), finish_reason: nil}], {:streaming, ref}}

        {:done, ^ref, {:error, reason}} ->
          {:halt, {:error, reason}}

        {:done, ^ref, _} ->
          {[%{delta: "", finish_reason: :stop}], {:done, ref}}
      after
        30_000 ->
          {:halt, {:error, :timeout}}
      end
    end

    defp continue_callback_streaming({:done, _ref}) do
      {:halt, :done}
    end

    defp normalize_stream_chunk(%{delta: delta}), do: delta
    defp normalize_stream_chunk(%{content: delta}), do: delta
    defp normalize_stream_chunk(delta) when is_binary(delta), do: delta
    defp normalize_stream_chunk(_), do: ""

    defp response_stream(content, reason) do
      Stream.concat([
        [%{delta: content, finish_reason: nil}],
        [%{delta: "", finish_reason: reason}]
      ])
    end

    defp blank?(value), do: value in [nil, ""]

    defp sdk_module do
      Application.get_env(:altar_ai, :claude_sdk, ClaudeAgentSDK)
    end
  end

  # Claude doesn't support embeddings - no Embedder impl
end
