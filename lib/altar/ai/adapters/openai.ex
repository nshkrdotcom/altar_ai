defmodule Altar.AI.Adapters.OpenAI do
  @moduledoc """
  OpenAI adapter using the openai_ex client.

  Provides text generation, streaming, and embeddings using the OpenAI
  chat completions and embeddings APIs.

  ## Options

    - `:api_key` - OpenAI API key (defaults to OPENAI_API_KEY env var)
    - `:organization` - OpenAI organization ID (defaults to OPENAI_ORGANIZATION)
    - `:project` - OpenAI project ID (defaults to OPENAI_PROJECT)
    - `:base_url` - Base URL override (e.g. for proxies) including `/v1`
    - `:receive_timeout` - HTTP receive timeout in ms
    - `:stream_timeout` - Streaming timeout in ms
    - `:model` - Default model to use (e.g. "gpt-4o")
    - `:embedding_model` - Optional embedding model override

  ## Example

      adapter = Altar.AI.Adapters.OpenAI.new(
        api_key: System.get_env("OPENAI_API_KEY"),
        model: "gpt-4o"
      )

      {:ok, response} = Altar.AI.generate(adapter, "Explain Elixir protocols")
  """

  defstruct opts: []

  @type t :: %__MODULE__{opts: keyword()}

  @default_models [
    "gpt-4o",
    "gpt-4o-mini",
    "gpt-4-turbo",
    "gpt-4",
    "gpt-3.5-turbo",
    "o1",
    "o1-mini",
    "o3-mini"
  ]

  @model_info %{
    "gpt-4o" => %{context_window: 128_000, max_output: 16_384, supports_tools: true},
    "gpt-4o-mini" => %{context_window: 128_000, max_output: 16_384, supports_tools: true},
    "gpt-4-turbo" => %{context_window: 128_000, max_output: 4096, supports_tools: true},
    "gpt-4" => %{context_window: 8_192, max_output: 8_192, supports_tools: true},
    "gpt-3.5-turbo" => %{context_window: 16_385, max_output: 4096, supports_tools: true},
    "o1" => %{context_window: 200_000, max_output: 100_000, supports_tools: false},
    "o1-mini" => %{context_window: 128_000, max_output: 65_536, supports_tools: false},
    "o3-mini" => %{context_window: 200_000, max_output: 100_000, supports_tools: true}
  }

  @doc """
  Create a new OpenAI adapter.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: %__MODULE__{opts: opts}

  # Check if OpenAI SDK available at compile time
  @openai_available Code.ensure_loaded?(OpenaiEx)

  @doc """
  Check if the OpenAI SDK (openai_ex) is available.
  """
  @spec available?() :: boolean()
  def available?, do: @openai_available

  @doc """
  List supported OpenAI models.
  """
  @spec supported_models() :: [String.t()]
  def supported_models, do: @default_models

  @doc """
  Get model info for a specific model.
  """
  @spec model_info(String.t()) :: map()
  def model_info(model) do
    Map.get(@model_info, model, default_model_info())
  end

  defp default_model_info do
    %{
      context_window: 128_000,
      max_output: 4096,
      supports_tools: true
    }
  end
end

if Code.ensure_loaded?(OpenaiEx) do
  defimpl Altar.AI.Generator, for: Altar.AI.Adapters.OpenAI do
    alias Altar.AI.{Error, Response, Telemetry}
    alias OpenaiEx.Chat.Completions
    alias OpenaiEx.ChatMessage

    def generate(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)
      model = merged_opts[:model] || "gpt-4o"

      Telemetry.span(:text_gen, %{provider: :openai, model: model}, fn ->
        with {:ok, client} <- build_client(merged_opts),
             {:ok, request} <- build_chat_request(prompt, merged_opts, model),
             {:ok, response} <- Completions.create(client, request) do
          {:ok, normalize_response(response, model)}
        else
          {:error, reason} -> {:error, Error.from_openai_error(reason)}
        end
      end)
    end

    def stream(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)
      model = merged_opts[:model] || "gpt-4o"

      Telemetry.span(:stream, %{provider: :openai, model: model}, fn ->
        with {:ok, client} <- build_client(merged_opts),
             {:ok, request} <- build_chat_request(prompt, merged_opts, model),
             {:ok, response} <- Completions.create(client, request, stream: true) do
          {:ok, build_stream(response)}
        else
          {:error, reason} -> {:error, Error.from_openai_error(reason)}
        end
      end)
    end

    defp build_client(opts) do
      api_key = opts[:api_key] || System.get_env("OPENAI_API_KEY")

      if is_nil(api_key) or api_key == "" do
        {:error, Error.new(:auth, "OpenAI API key missing", provider: :openai, retryable?: false)}
      else
        org = opts[:organization] || System.get_env("OPENAI_ORGANIZATION")
        project = opts[:project] || System.get_env("OPENAI_PROJECT")

        client =
          OpenaiEx.new(api_key, org, project)
          |> maybe_put_base_url(opts)
          |> maybe_put_receive_timeout(opts)
          |> maybe_put_stream_timeout(opts)

        {:ok, client}
      end
    end

    defp maybe_put_base_url(client, opts) do
      case opts[:base_url] do
        nil -> client
        url -> OpenaiEx.with_base_url(client, url)
      end
    end

    defp maybe_put_receive_timeout(client, opts) do
      case opts[:receive_timeout] do
        nil -> client
        timeout -> OpenaiEx.with_receive_timeout(client, timeout)
      end
    end

    defp maybe_put_stream_timeout(client, opts) do
      case opts[:stream_timeout] do
        nil -> client
        timeout -> OpenaiEx.with_stream_timeout(client, timeout)
      end
    end

    defp build_chat_request(prompt, opts, model) do
      messages = build_messages(prompt, opts)

      request =
        Completions.new(
          model: model,
          messages: messages
        )
        |> maybe_put(:max_tokens, opts[:max_tokens])
        |> maybe_put(:temperature, opts[:temperature])
        |> maybe_put(:top_p, opts[:top_p])
        |> maybe_put(:frequency_penalty, opts[:frequency_penalty])
        |> maybe_put(:presence_penalty, opts[:presence_penalty])
        |> maybe_put(:seed, opts[:seed])
        |> maybe_put(:stop, opts[:stop])
        |> maybe_put(:user, opts[:user])

      {:ok, request}
    end

    defp build_messages(prompt, opts) do
      base_messages =
        cond do
          is_list(prompt) ->
            prompt

          is_list(opts[:messages]) ->
            opts[:messages] ++ [%{role: "user", content: prompt}]

          true ->
            [%{role: "user", content: prompt}]
        end

      system_prompt = opts[:system] || opts[:system_prompt]

      messages =
        if system_prompt && !has_system_message?(base_messages) do
          [%{role: "system", content: system_prompt} | base_messages]
        else
          base_messages
        end

      Enum.map(messages, &to_chat_message/1)
    end

    defp has_system_message?(messages) do
      Enum.any?(messages, fn
        %{role: role} -> to_string(role) == "system"
        %{"role" => role} -> to_string(role) == "system"
        _ -> false
      end)
    end

    defp to_chat_message(%{role: role, content: content, name: name}) do
      %{role: to_string(role), content: content, name: name}
    end

    defp to_chat_message(%{role: role, content: content}) do
      build_message(to_string(role), content)
    end

    defp to_chat_message(%{"role" => role, "content" => content}) do
      build_message(to_string(role), content)
    end

    defp to_chat_message(message) when is_map(message), do: message

    defp build_message("system", content), do: ChatMessage.system(content)
    defp build_message("developer", content), do: ChatMessage.developer(content)
    defp build_message("assistant", content), do: ChatMessage.assistant(content)
    defp build_message("user", content), do: ChatMessage.user(content)
    defp build_message(_, content), do: ChatMessage.user(content)

    defp normalize_response(response, model) do
      choice = Enum.at(Map.get(response, "choices", []), 0, %{})
      message = Map.get(choice, "message", %{})
      usage = Map.get(response, "usage", %{})
      prompt_tokens = Map.get(usage, "prompt_tokens", 0)
      completion_tokens = Map.get(usage, "completion_tokens", 0)
      total_tokens = Map.get(usage, "total_tokens", prompt_tokens + completion_tokens)

      %Response{
        content: Map.get(message, "content", ""),
        model: Map.get(response, "model", model),
        provider: :openai,
        finish_reason: normalize_finish_reason(Map.get(choice, "finish_reason")),
        tokens: %{prompt: prompt_tokens, completion: completion_tokens, total: total_tokens}
      }
    end

    defp normalize_finish_reason("stop"), do: :stop
    defp normalize_finish_reason("length"), do: :length
    defp normalize_finish_reason("tool_calls"), do: :tool_use
    defp normalize_finish_reason("content_filter"), do: :content_filter
    defp normalize_finish_reason(nil), do: nil
    defp normalize_finish_reason(_), do: :stop

    defp build_stream(stream_response) do
      stream_response.body_stream
      |> Stream.flat_map(& &1)
      |> Stream.transform(:init, &handle_stream_event/2)
      |> Stream.concat([%{delta: "", finish_reason: :stop}])
    end

    defp handle_stream_event(event, state) do
      case event do
        %{data: data} when is_map(data) ->
          handle_stream_data(data, state)

        _ ->
          {[], state}
      end
    end

    defp handle_stream_data(data, state) do
      choice = List.first(data["choices"] || []) || %{}
      delta = choice["delta"] || %{}
      content = delta["content"]
      finish_reason = choice["finish_reason"]

      cond do
        is_binary(content) and content != "" ->
          {[%{delta: content, finish_reason: nil}], state}

        not is_nil(finish_reason) ->
          {[%{delta: "", finish_reason: normalize_finish_reason(finish_reason)}], state}

        true ->
          {[], state}
      end
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)
  end

  defimpl Altar.AI.Embedder, for: Altar.AI.Adapters.OpenAI do
    alias Altar.AI.Error
    alias OpenaiEx.Embeddings

    def embed(%{opts: opts}, text, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)

      with {:ok, client} <- build_client(merged_opts),
           {:ok, request} <- build_embed_request([text], merged_opts),
           {:ok, response} <- Embeddings.create(client, request),
           {:ok, vector} <- extract_first_embedding(response) do
        {:ok, vector}
      else
        {:error, reason} -> {:error, Error.from_openai_error(reason)}
      end
    end

    def batch_embed(%{opts: opts}, texts, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)

      with {:ok, client} <- build_client(merged_opts),
           {:ok, request} <- build_embed_request(texts, merged_opts),
           {:ok, response} <- Embeddings.create(client, request),
           {:ok, vectors} <- extract_embeddings(response) do
        {:ok, vectors}
      else
        {:error, reason} -> {:error, Error.from_openai_error(reason)}
      end
    end

    defp build_client(opts) do
      api_key = opts[:api_key] || System.get_env("OPENAI_API_KEY")

      if is_nil(api_key) or api_key == "" do
        {:error, Error.new(:auth, "OpenAI API key missing", provider: :openai, retryable?: false)}
      else
        org = opts[:organization] || System.get_env("OPENAI_ORGANIZATION")
        project = opts[:project] || System.get_env("OPENAI_PROJECT")

        client =
          OpenaiEx.new(api_key, org, project)
          |> maybe_put_base_url(opts)
          |> maybe_put_receive_timeout(opts)

        {:ok, client}
      end
    end

    defp maybe_put_base_url(client, opts) do
      case opts[:base_url] do
        nil -> client
        url -> OpenaiEx.with_base_url(client, url)
      end
    end

    defp maybe_put_receive_timeout(client, opts) do
      case opts[:receive_timeout] do
        nil -> client
        timeout -> OpenaiEx.with_receive_timeout(client, timeout)
      end
    end

    defp build_embed_request(texts, opts) do
      model = opts[:embedding_model] || opts[:model] || "text-embedding-3-small"

      request =
        Embeddings.new(
          model: model,
          input: texts
        )
        |> maybe_put(:dimensions, opts[:dimensions])
        |> maybe_put(:encoding_format, opts[:encoding_format])
        |> maybe_put(:user, opts[:user])

      {:ok, request}
    end

    defp extract_first_embedding(response) do
      case response["data"] do
        [%{"embedding" => vector} | _] when is_list(vector) ->
          {:ok, vector}

        _ ->
          {:error,
           Error.new(:unknown, "OpenAI embedding response missing data", provider: :openai)}
      end
    end

    defp extract_embeddings(response) do
      data = response["data"] || []

      vectors =
        data
        |> Enum.sort_by(& &1["index"])
        |> Enum.map(& &1["embedding"])

      if Enum.all?(vectors, &is_list/1) do
        {:ok, vectors}
      else
        {:error, Error.new(:unknown, "OpenAI embedding response missing data", provider: :openai)}
      end
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)
  end
end
