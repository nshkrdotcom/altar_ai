defmodule Altar.AI.Client do
  @moduledoc """
  High-level unified client for Altar.AI operations.

  The Client provides a convenient interface for AI operations that:
  - Uses profile-based configuration via `Altar.AI.Config`
  - Automatically resolves adapters and options
  - Wraps operations with telemetry
  - Provides compatibility interfaces (e.g., `chat_completion/3` for ReqLLM)

  ## Example

      client =
        Client.new()
        |> Client.with_profile(:gemini,
          adapter: Altar.AI.Adapters.Gemini.new(api_key: "..."),
          model: "gemini-pro"
        )
        |> Client.with_profile(:claude,
          adapter: Altar.AI.Adapters.Claude.new(api_key: "..."),
          model: "claude-3-opus"
        )
        |> Client.with_default_profile(:gemini)

      # Use default profile
      {:ok, response} = Client.generate(client, "Hello, world!")

      # Use specific profile
      {:ok, response} = Client.generate(client, "Hello!", profile: :claude)

  ## ReqLLM Compatibility

  The `chat_completion/3` function provides compatibility with Synapse's ReqLLM interface:

      {:ok, response} = Client.chat_completion(client, %{
        prompt: "What is 2+2?",
        messages: [%{role: "system", content: "You are helpful."}]
      })
  """

  alias Altar.AI.{Capabilities, Config, Telemetry}
  alias Altar.AI.{Classifier, Embedder, Generator}

  @type t :: %__MODULE__{
          config: Config.t()
        }

  defstruct [:config]

  @doc """
  Creates a new Client with the given options.

  ## Options

    * `:config` - An `Altar.AI.Config` struct (optional)

  ## Examples

      Client.new()
      Client.new(config: Config.new(default_profile: :gemini))
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    config = Keyword.get(opts, :config, Config.new())
    %__MODULE__{config: config}
  end

  @doc """
  Adds a profile to the client's configuration.

  ## Examples

      client
      |> Client.with_profile(:gemini, adapter: Gemini.new(), model: "gemini-pro")
  """
  @spec with_profile(t(), atom(), keyword()) :: t()
  def with_profile(%__MODULE__{config: config} = client, name, opts) do
    %{client | config: Config.add_profile(config, name, opts)}
  end

  @doc """
  Sets the default profile for the client.

  ## Examples

      client
      |> Client.with_default_profile(:gemini)
  """
  @spec with_default_profile(t(), atom()) :: t()
  def with_default_profile(%__MODULE__{config: config} = client, profile) do
    %{client | config: %{config | default_profile: profile}}
  end

  @doc """
  Generates text using the configured adapter.

  ## Options

    * `:profile` - The profile to use (defaults to client's default profile)
    * Other options are passed through to the adapter

  ## Examples

      {:ok, response} = Client.generate(client, "Hello, world!")
      {:ok, response} = Client.generate(client, "Hello!", profile: :claude)
  """
  @spec generate(t(), String.t(), keyword()) :: {:ok, Altar.AI.Response.t()} | {:error, term()}
  def generate(%__MODULE__{} = client, prompt, opts \\ []) do
    {profile, call_opts} = Keyword.pop(opts, :profile, client.config.default_profile)
    resolved_opts = Config.resolve_opts(client.config, profile, call_opts)

    case get_adapter(client, profile) do
      nil ->
        {:error,
         %Altar.AI.Error{type: :invalid_request, message: "No adapter for profile #{profile}"}}

      adapter ->
        metadata =
          %{provider: adapter_provider(adapter), profile: profile}
          |> Map.merge(extract_command_metadata(resolved_opts))

        Telemetry.span(:generate, metadata, fn ->
          Generator.generate(adapter, prompt, resolved_opts)
        end)
    end
  end

  @doc """
  Streams text generation using the configured adapter.

  ## Options

    * `:profile` - The profile to use (defaults to client's default profile)
    * Other options are passed through to the adapter

  ## Examples

      {:ok, stream} = Client.stream(client, "Tell me a story")
  """
  @spec stream(t(), String.t(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(%__MODULE__{} = client, prompt, opts \\ []) do
    {profile, call_opts} = Keyword.pop(opts, :profile, client.config.default_profile)
    resolved_opts = Config.resolve_opts(client.config, profile, call_opts)

    case get_adapter(client, profile) do
      nil ->
        {:error,
         %Altar.AI.Error{type: :invalid_request, message: "No adapter for profile #{profile}"}}

      adapter ->
        metadata =
          %{provider: adapter_provider(adapter), profile: profile, streaming: true}
          |> Map.merge(extract_command_metadata(resolved_opts))

        Telemetry.span(:generate, metadata, fn ->
          Generator.stream(adapter, prompt, resolved_opts)
        end)
    end
  end

  @doc """
  Generates embeddings for text.

  ## Options

    * `:profile` - The profile to use (defaults to client's default profile)
    * Other options are passed through to the adapter

  ## Examples

      {:ok, embedding} = Client.embed(client, "Hello world")
  """
  @spec embed(t(), String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(%__MODULE__{} = client, text, opts \\ []) do
    {profile, call_opts} = Keyword.pop(opts, :profile, client.config.default_profile)
    resolved_opts = Config.resolve_opts(client.config, profile, call_opts)

    case get_adapter(client, profile) do
      nil ->
        {:error,
         %Altar.AI.Error{type: :invalid_request, message: "No adapter for profile #{profile}"}}

      adapter ->
        metadata =
          %{provider: adapter_provider(adapter), profile: profile}
          |> Map.merge(extract_command_metadata(resolved_opts))

        Telemetry.span(:embed, metadata, fn ->
          Embedder.embed(adapter, text, resolved_opts)
        end)
    end
  end

  @doc """
  Generates batch embeddings for multiple texts.

  ## Options

    * `:profile` - The profile to use (defaults to client's default profile)
    * Other options are passed through to the adapter

  ## Examples

      {:ok, embeddings} = Client.batch_embed(client, ["Hello", "World"])
  """
  @spec batch_embed(t(), [String.t()], keyword()) :: {:ok, [[float()]]} | {:error, term()}
  def batch_embed(%__MODULE__{} = client, texts, opts \\ []) do
    {profile, call_opts} = Keyword.pop(opts, :profile, client.config.default_profile)
    resolved_opts = Config.resolve_opts(client.config, profile, call_opts)

    case get_adapter(client, profile) do
      nil ->
        {:error,
         %Altar.AI.Error{type: :invalid_request, message: "No adapter for profile #{profile}"}}

      adapter ->
        metadata =
          %{
            provider: adapter_provider(adapter),
            profile: profile,
            batch: true,
            count: length(texts)
          }
          |> Map.merge(extract_command_metadata(resolved_opts))

        Telemetry.span(:embed, metadata, fn ->
          Embedder.batch_embed(adapter, texts, resolved_opts)
        end)
    end
  end

  @doc """
  Classifies text into one of the given labels.

  ## Options

    * `:profile` - The profile to use (defaults to client's default profile)
    * Other options are passed through to the adapter

  ## Examples

      {:ok, result} = Client.classify(client, "Great product!", ["positive", "negative"])
  """
  @spec classify(t(), String.t(), [String.t()], keyword()) ::
          {:ok, Altar.AI.Classification.t()} | {:error, term()}
  def classify(%__MODULE__{} = client, text, labels, opts \\ []) do
    {profile, call_opts} = Keyword.pop(opts, :profile, client.config.default_profile)
    resolved_opts = Config.resolve_opts(client.config, profile, call_opts)

    case get_adapter(client, profile) do
      nil ->
        {:error,
         %Altar.AI.Error{type: :invalid_request, message: "No adapter for profile #{profile}"}}

      adapter ->
        metadata =
          %{provider: adapter_provider(adapter), profile: profile, label_count: length(labels)}
          |> Map.merge(extract_command_metadata(resolved_opts))

        Telemetry.span(:classify, metadata, fn ->
          Classifier.classify(adapter, text, labels, resolved_opts)
        end)
    end
  end

  @doc """
  Chat completion interface for ReqLLM compatibility.

  This function provides compatibility with Synapse's ReqLLM interface.

  ## Parameters

    * `params` - A map with:
      * `:prompt` - The main prompt (required)
      * `:messages` - Optional list of prior messages
      * `:temperature` - Optional temperature
      * `:max_tokens` - Optional max tokens
    * `opts` - Options:
      * `:profile` - The profile to use

  ## Returns

  Returns `{:ok, response}` where response has:
    * `:content` - The generated text
    * `:metadata` - Map with `:total_tokens` if available

  ## Examples

      {:ok, response} = Client.chat_completion(client, %{
        prompt: "What is 2+2?",
        messages: [%{role: "system", content: "You are helpful."}]
      })
  """
  @spec chat_completion(t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def chat_completion(%__MODULE__{} = client, params, opts \\ []) do
    prompt = build_prompt_from_params(params)
    call_opts = extract_call_opts(params, opts)

    case generate(client, prompt, call_opts) do
      {:ok, response} ->
        {:ok, normalize_chat_response(response)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets the adapter for a specific profile.

  Returns `nil` if the profile doesn't exist or has no adapter.

  ## Examples

      adapter = Client.get_adapter(client, :gemini)
  """
  @spec get_adapter(t(), atom()) :: term() | nil
  def get_adapter(%__MODULE__{config: config}, profile) do
    resolved_profile =
      if profile == :default do
        config.default_profile
      else
        profile
      end

    Config.get_adapter(config, resolved_profile)
  end

  @doc """
  Gets the capabilities of the adapter for a profile.

  ## Examples

      caps = Client.capabilities(client, :gemini)
      caps.generate  #=> true
  """
  @spec capabilities(t(), atom()) :: Capabilities.capability_map()
  def capabilities(%__MODULE__{} = client, profile) do
    case get_adapter(client, profile) do
      nil -> Capabilities.capabilities(nil)
      adapter -> Capabilities.capabilities(adapter)
    end
  end

  # Private helpers

  defp build_prompt_from_params(params) do
    # Build prompt from messages + main prompt
    messages = Map.get(params, :messages, [])
    main_prompt = Map.get(params, :prompt, "")

    case messages do
      [] ->
        main_prompt

      msgs ->
        # Combine system messages and user messages with the main prompt
        message_text =
          Enum.map_join(msgs, "\n", fn msg ->
            role = Map.get(msg, :role, Map.get(msg, "role", "user"))
            content = Map.get(msg, :content, Map.get(msg, "content", ""))
            "[#{role}]: #{content}"
          end)

        "#{message_text}\n\n#{main_prompt}"
    end
  end

  defp extract_call_opts(params, opts) do
    param_opts =
      params
      |> Map.take([:temperature, :max_tokens, :model])
      |> Enum.to_list()

    Keyword.merge(param_opts, opts)
  end

  defp normalize_chat_response(response) do
    metadata = %{total_tokens: response.tokens.total}

    %{
      content: response.content,
      model: response.model,
      provider: response.provider,
      finish_reason: response.finish_reason,
      metadata: metadata
    }
  end

  defp adapter_provider(adapter) when is_struct(adapter) do
    adapter.__struct__
    |> Module.split()
    |> List.last()
    |> String.downcase()
    |> String.to_atom()
  end

  defp adapter_provider(adapter) when is_atom(adapter) do
    adapter
    |> Module.split()
    |> List.last()
    |> String.downcase()
    |> String.to_atom()
  end

  defp adapter_provider(_), do: :unknown

  defp extract_command_metadata(opts) do
    [:command_session_id, :command_workflow_id, :command_user_id, :correlation_id, :request_id]
    |> Enum.reduce(%{}, fn key, acc ->
      case Keyword.get(opts, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end
end
