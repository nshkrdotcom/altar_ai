defmodule Altar.AI.Adapters.Codex do
  @moduledoc """
  Codex/OpenAI adapter wrapping codex_sdk.

  Provides protocol implementations for OpenAI capabilities including
  text generation, streaming, and code generation.

  This adapter uses the `codex_sdk` hex package. The SDK must be available
  at compile time for protocol implementations to be defined.

  ## Features

  - Text generation with thread-based API
  - Streaming via Codex.Thread.run_streamed
  - Code generation and explanation
  - Token usage tracking

  ## Models

  Common models include:
  - "gpt-4o" (GPT-4 Optimized)
  - "gpt-4o-mini" (GPT-4 Mini)
  - "gpt-4-turbo" (GPT-4 Turbo)
  - "o1" (Reasoning model)
  - "o3-mini" (Reasoning mini model)

  ## Example

      # Create adapter with default options
      adapter = Altar.AI.Adapters.Codex.new()

      # Create with custom model
      adapter = Altar.AI.Adapters.Codex.new(model: "gpt-4o")

      # Generate text
      {:ok, response} = Altar.AI.generate(adapter, "What is Elixir?")

      # Generate code
      {:ok, result} = Altar.AI.generate_code(adapter, "FizzBuzz in Elixir")
  """

  require Logger

  defstruct opts: []

  @type t :: %__MODULE__{opts: keyword()}

  @default_models ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o1", "o3-mini"]

  @doc """
  Create a new Codex adapter.

  ## Options

    - `:api_key` - OpenAI API key (defaults to OPENAI_API_KEY env var via SDK)
    - `:model` - Default model to use (e.g., "gpt-4o")
    - `:temperature` - Sampling temperature
    - `:max_tokens` - Maximum tokens in response
    - `:system` - System prompt for the model
    - Other options passed through to codex_sdk

  ## Examples

      iex> Altar.AI.Adapters.Codex.new(model: "gpt-4o")
      %Altar.AI.Adapters.Codex{opts: [model: "gpt-4o"]}

      iex> Altar.AI.Adapters.Codex.new(model: "gpt-4-turbo", temperature: 0.7)
      %Altar.AI.Adapters.Codex{opts: [model: "gpt-4-turbo", temperature: 0.7]}
  """
  def new(opts \\ []), do: %__MODULE__{opts: opts}

  @doc """
  Check if the Codex SDK (codex_sdk) is available.

  Returns `true` if the codex_sdk library is loaded and available.
  """
  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(Codex)

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
      context_window: 128_000,
      max_output: 4096,
      supports_tools: true
    }
  end

  defp sdk_module do
    Application.get_env(:altar_ai, :codex_sdk, Codex)
  end
end

if Code.ensure_loaded?(Codex) do
  defimpl Altar.AI.Generator, for: Altar.AI.Adapters.Codex do
    alias Altar.AI.{Error, Response, Telemetry}

    require Logger

    def generate(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)
      model = merged_opts[:model] || "gpt-4o"
      sdk = sdk_module()

      Telemetry.span(:text_gen, %{provider: :codex, model: model}, fn ->
        cond do
          function_exported?(sdk, :complete, 2) ->
            complete_via_sdk(sdk, prompt, merged_opts, model)

          function_exported?(sdk, :start_thread, 2) ->
            complete_via_thread(prompt, merged_opts, model)

          Code.ensure_loaded?(Codex) and function_exported?(Codex, :start_thread, 2) ->
            complete_via_thread(prompt, merged_opts, model)

          true ->
            {:error, Error.new(:unsupported, "No supported completion method", provider: :codex)}
        end
      end)
    end

    def stream(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)
      model = merged_opts[:model] || "gpt-4o"
      sdk = sdk_module()

      Telemetry.span(:stream, %{provider: :codex, model: model}, fn ->
        cond do
          function_exported?(sdk, :stream, 2) or function_exported?(sdk, :stream, 3) ->
            stream_via_sdk(sdk, prompt, merged_opts, model)

          function_exported?(sdk, :start_thread, 2) ->
            stream_via_thread(prompt, merged_opts, model)

          Code.ensure_loaded?(Codex) and function_exported?(Codex, :start_thread, 2) ->
            stream_via_thread(prompt, merged_opts, model)

          function_exported?(sdk, :complete, 2) ->
            stream_from_complete(sdk, prompt, merged_opts, model)

          true ->
            {:error, Error.new(:unsupported, "Streaming not supported", provider: :codex)}
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
          Logger.error("Codex completion failed: #{inspect(reason)}")
          {:error, Error.new(:api_error, inspect(reason), provider: :codex)}
      end
    end

    defp complete_via_thread(prompt, opts, model) do
      {system_prompt, actual_prompt} = extract_system_prompt(prompt, opts)
      actual_prompt = apply_system_prompt(actual_prompt, system_prompt)

      with {:ok, thread} <- start_thread(opts, model),
           {:ok, result} <- Codex.Thread.run(thread, actual_prompt, build_run_opts(opts, model)) do
        response = normalize_codex_result(result, model)
        {:ok, response}
      else
        {:error, reason} ->
          Logger.error("Codex completion failed: #{inspect(reason)}")
          {:error, Error.new(:api_error, inspect(reason), provider: :codex)}
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
          {:error, Error.new(:unsupported, "Stream not supported", provider: :codex)}
      end
    end

    defp stream_via_thread(prompt, opts, model) do
      {system_prompt, actual_prompt} = extract_system_prompt(prompt, opts)
      actual_prompt = apply_system_prompt(actual_prompt, system_prompt)

      with {:ok, thread} <- start_thread(opts, model),
           {:ok, result} <-
             Codex.Thread.run_streamed(thread, actual_prompt, build_run_opts(opts, model)) do
        {:ok, codex_stream(result)}
      else
        {:error, reason} ->
          Logger.error("Codex streaming failed: #{inspect(reason)}")
          {:error, Error.new(:api_error, inspect(reason), provider: :codex)}
      end
    end

    defp stream_from_complete(sdk, prompt, opts, model) do
      case complete_via_sdk(sdk, prompt, opts, model) do
        {:ok, response} ->
          {:ok, response_stream(response.content, response.finish_reason)}

        {:error, _} = error ->
          error
      end
    end

    defp start_thread(_opts, model) do
      codex_opts =
        %{}
        |> maybe_put_map(:model, model)

      Codex.start_thread(codex_opts, %{})
    end

    defp build_run_opts(opts, model) do
      max_tokens = opts[:max_tokens]

      run_config =
        %{}
        |> Map.put(:max_turns, 1)
        |> maybe_put_map(:model, model)
        |> maybe_put_map(:model_settings, build_model_settings(max_tokens))

      %{run_config: run_config}
    end

    defp build_model_settings(nil), do: nil

    defp build_model_settings(tokens) when is_integer(tokens) and tokens > 0 do
      %{max_tokens: tokens}
    end

    defp build_model_settings(_), do: nil

    defp build_sdk_options(opts, model) do
      opts
      |> Keyword.take([:api_key, :temperature, :max_tokens, :top_p, :system])
      |> Keyword.put(:model, model)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    end

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

    defp extract_system_prompt(prompt, opts) when is_binary(prompt) do
      system_opt = opts[:system] || opts[:system_prompt]
      {system_opt, prompt}
    end

    defp extract_system_prompt(messages, opts) when is_list(messages) do
      system_opt = opts[:system] || opts[:system_prompt]

      {system_messages, rest} = Enum.split_with(messages, &system_message?/1)
      system_prompt = system_opt || first_system_content(system_messages)
      prompt = format_conversation(rest)

      {system_prompt, prompt}
    end

    defp system_message?(%{role: role}), do: to_string(role) == "system"
    defp system_message?(%{"role" => role}), do: to_string(role) == "system"
    defp system_message?(_), do: false

    defp first_system_content([]), do: nil
    defp first_system_content([message | _]), do: message_content(message)

    defp message_content(%{content: content}), do: content
    defp message_content(%{"content" => content}), do: content
    defp message_content(_), do: nil

    defp apply_system_prompt(prompt, nil), do: prompt

    defp apply_system_prompt(prompt, system_prompt)
         when is_binary(system_prompt) and system_prompt != "" do
      if prompt == "" do
        system_prompt
      else
        "System: #{system_prompt}\n\n#{prompt}"
      end
    end

    defp apply_system_prompt(prompt, _system_prompt), do: prompt

    defp format_conversation(messages) do
      messages
      |> Enum.map(&format_message/1)
      |> Enum.reject(&blank?/1)
      |> Enum.join("\n\n")
    end

    defp format_message(message) do
      role = message_role(message) || "user"
      content = message_content(message)

      if is_binary(content) and content != "" do
        "#{String.capitalize(to_string(role))}: #{content}"
      else
        ""
      end
    end

    defp message_role(%{role: role}), do: role
    defp message_role(%{"role" => role}), do: role
    defp message_role(_), do: nil

    defp codex_stream(result) do
      Codex.RunResultStreaming.events(result)
      |> Stream.transform(%{emitted?: false}, &handle_codex_event/2)
      |> Stream.concat([%{delta: "", finish_reason: :stop}])
    end

    defp handle_codex_event(
           %Codex.StreamEvent.RunItem{event: %Codex.Events.ItemAgentMessageDelta{item: item}},
           state
         ) do
      case extract_delta(item) do
        nil -> {[], state}
        delta -> {[%{delta: delta, finish_reason: nil}], %{state | emitted?: true}}
      end
    end

    defp handle_codex_event(
           %Codex.StreamEvent.RunItem{event: %Codex.Events.ItemCompleted{item: item}},
           state
         ) do
      case {state.emitted?, extract_item_text(item)} do
        {false, text} when is_binary(text) and text != "" ->
          {[%{delta: text, finish_reason: nil}], %{state | emitted?: true}}

        _ ->
          {[], state}
      end
    end

    defp handle_codex_event(_event, state), do: {[], state}

    defp extract_delta(%{"text" => text}) when is_binary(text), do: text
    defp extract_delta(%{text: text}) when is_binary(text), do: text

    defp extract_delta(%{"content" => %{"type" => "text", "text" => text}})
         when is_binary(text),
         do: text

    defp extract_delta(%{content: %{type: "text", text: text}}) when is_binary(text), do: text
    defp extract_delta(_), do: nil

    defp extract_item_text(%Codex.Items.AgentMessage{text: text}) when is_binary(text), do: text
    defp extract_item_text(%{"text" => text}) when is_binary(text), do: text
    defp extract_item_text(%{text: text}) when is_binary(text), do: text
    defp extract_item_text(_), do: nil

    defp normalize_codex_result(%Codex.Turn.Result{} = result, default_model) do
      %Response{
        content: codex_content(result),
        model: codex_model(result) || default_model,
        provider: :codex,
        finish_reason: codex_finish_reason(result.events),
        tokens: normalize_usage(result.usage)
      }
    end

    defp codex_content(%Codex.Turn.Result{final_response: %Codex.Items.AgentMessage{text: text}})
         when is_binary(text),
         do: text

    defp codex_content(%Codex.Turn.Result{final_response: %{"text" => text}})
         when is_binary(text),
         do: text

    defp codex_content(%Codex.Turn.Result{final_response: %{text: text}}) when is_binary(text),
      do: text

    defp codex_content(_), do: ""

    defp codex_model(%Codex.Turn.Result{
           thread: %Codex.Thread{codex_opts: %Codex.Options{model: model}}
         })
         when is_binary(model) and model != "",
         do: model

    defp codex_model(_), do: nil

    defp codex_finish_reason(events) do
      events
      |> List.wrap()
      |> Enum.find(&match?(%Codex.Events.TurnCompleted{}, &1))
      |> case do
        %Codex.Events.TurnCompleted{status: status} -> normalize_codex_status(status)
        _ -> :stop
      end
    end

    defp normalize_codex_status(status) when status in ["early_exit", :early_exit], do: :length
    defp normalize_codex_status(_), do: :stop

    defp normalize_usage(%{} = usage) do
      input =
        Map.get(usage, :input_tokens) ||
          Map.get(usage, "input_tokens") ||
          Map.get(usage, :prompt_tokens) ||
          Map.get(usage, "prompt_tokens") ||
          0

      output =
        Map.get(usage, :output_tokens) ||
          Map.get(usage, "output_tokens") ||
          Map.get(usage, :completion_tokens) ||
          Map.get(usage, "completion_tokens") ||
          0

      %{prompt: input, completion: output, total: input + output}
    end

    defp normalize_usage(_), do: %{prompt: 0, completion: 0, total: 0}

    defp normalize_response(response, model) do
      %Response{
        content: response_content(response),
        model: response_model(response) || model,
        provider: :codex,
        finish_reason: normalize_finish_reason_value(response_finish_reason(response)),
        tokens: normalize_usage(response_usage(response))
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

    defp normalize_finish_reason_value(nil), do: :stop
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
      finish_reason = reason || :stop

      Stream.concat([
        [%{delta: content, finish_reason: nil}],
        [%{delta: "", finish_reason: finish_reason}]
      ])
    end

    defp blank?(value), do: value in [nil, ""]

    defp maybe_put_map(map, _key, nil), do: map
    defp maybe_put_map(map, key, value), do: Map.put(map, key, value)

    defp sdk_module do
      Application.get_env(:altar_ai, :codex_sdk, Codex)
    end
  end

  defimpl Altar.AI.CodeGenerator, for: Altar.AI.Adapters.Codex do
    alias Altar.AI.{CodeResult, Error, Telemetry}

    require Logger

    def generate_code(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)
      model = merged_opts[:model] || "gpt-4o"

      Telemetry.span(:code_gen, %{provider: :codex, model: model}, fn ->
        with {:ok, thread} <- Codex.start_thread(%{model: model}, %{}),
             {:ok, result} <- Codex.Thread.run(thread, "Generate code: #{prompt}", %{}) do
          code = extract_code(result.final_response)

          {:ok,
           %CodeResult{
             code: code,
             language: merged_opts[:language],
             metadata: %{model: model}
           }}
        else
          {:error, error} ->
            Logger.error("Codex code generation failed: #{inspect(error)}")
            {:error, Error.new(:api_error, inspect(error), provider: :codex)}
        end
      end)
    end

    def explain_code(%{opts: opts}, code, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)
      model = merged_opts[:model] || "gpt-4o"

      Telemetry.span(:explain_code, %{provider: :codex, model: model}, fn ->
        with {:ok, thread} <- Codex.start_thread(%{model: model}, %{}),
             {:ok, result} <- Codex.Thread.run(thread, "Explain this code:\n\n#{code}", %{}) do
          explanation = extract_text(result.final_response)
          {:ok, explanation}
        else
          {:error, error} ->
            Logger.error("Codex code explanation failed: #{inspect(error)}")
            {:error, Error.new(:api_error, inspect(error), provider: :codex)}
        end
      end)
    end

    defp extract_code(response) do
      text = extract_text(response)

      # Try to extract code from markdown code blocks
      case Regex.run(~r/```(?:\w+\n)?(.*?)```/s, text) do
        [_, code] -> String.trim(code)
        _ -> text
      end
    end

    defp extract_text(%Codex.Items.AgentMessage{text: text}) when is_binary(text), do: text

    defp extract_text(%{content: content}) when is_list(content) do
      Enum.map_join(content, "\n", fn
        %{text: %{value: text}} -> text
        %{text: text} when is_binary(text) -> text
        _ -> ""
      end)
    end

    defp extract_text(%{"text" => text}), do: cast_text(text)
    defp extract_text(%{text: text}), do: cast_text(text)
    defp extract_text(_), do: ""

    defp cast_text(text) when is_binary(text), do: text
    defp cast_text(_), do: ""
  end
end
