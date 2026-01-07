defmodule Altar.AI.Adapters.Gemini do
  @moduledoc """
  Gemini adapter wrapping gemini_ex.

  Provides protocol implementations for Gemini AI capabilities including
  text generation, streaming, and embeddings.

  This adapter uses the `gemini_ex` hex package. The SDK must be available
  at compile time for protocol implementations to be defined.

  ## Features

  - Text generation with configurable parameters
  - Streaming text generation with callbacks
  - Single and batch embedding generation
  - Automatic model resolution via gemini_ex registry
  - Token usage tracking and telemetry

  ## Models

  Uses the gemini_ex registry defaults unless a model is supplied via options.
  See `Gemini.Config.models_for/1` for available models.

  ## Example

      # Create adapter with default options
      adapter = Altar.AI.Adapters.Gemini.new()

      # Create with custom model
      adapter = Altar.AI.Adapters.Gemini.new(model: "gemini-1.5-pro")

      # Generate text
      {:ok, response} = Altar.AI.generate(adapter, "What is Elixir?")

      # Generate embeddings
      {:ok, vector} = Altar.AI.embed(adapter, "semantic search text")
  """

  # Suppress dialyzer warnings for gemini_ex API calls
  @dialyzer [
    :no_return,
    :no_match,
    :no_fail_call
  ]

  defstruct opts: []

  @type t :: %__MODULE__{opts: keyword()}

  @doc """
  Create a new Gemini adapter.

  ## Options

    - `:api_key` - Gemini API key (defaults to GEMINI_API_KEY env var via gemini_ex)
    - `:model` - Default model to use (e.g., "gemini-pro", "gemini-1.5-pro")
    - `:temperature` - Sampling temperature (0.0 to 1.0)
    - `:max_tokens` or `:max_output_tokens` - Maximum tokens in response
    - `:system_instruction` - System prompt for the model
    - Other options passed through to gemini_ex

  ## Examples

      iex> Altar.AI.Adapters.Gemini.new(model: "gemini-1.5-pro")
      %Altar.AI.Adapters.Gemini{opts: [model: "gemini-1.5-pro"]}

      iex> Altar.AI.Adapters.Gemini.new(model: "gemini-pro", temperature: 0.7)
      %Altar.AI.Adapters.Gemini{opts: [model: "gemini-pro", temperature: 0.7]}
  """
  def new(opts \\ []), do: %__MODULE__{opts: opts}

  @doc """
  Check if the Gemini SDK (gemini_ex) is available.

  Returns `true` if the gemini_ex library is loaded and available.
  """
  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(Gemini)

  @doc """
  List supported generation models.

  Returns a list of model identifiers that can be used for text generation.
  Requires gemini_ex to be available.
  """
  @spec supported_models() :: [String.t()]
  def supported_models do
    if available?() and config_available?() do
      models_for_current_api()
      |> Map.values()
      |> Enum.reject(&embedding_model?/1)
    else
      []
    end
  end

  @doc """
  List supported embedding models.

  Returns a list of model identifiers that can be used for embeddings.
  Requires gemini_ex to be available.
  """
  @spec supported_embedding_models() :: [String.t()]
  def supported_embedding_models do
    if available?() and config_available?() do
      models_for_current_api()
      |> Map.values()
      |> Enum.filter(&embedding_model?/1)
    else
      []
    end
  end

  defp embedding_model?(model) when is_binary(model) do
    config_module = config_module()

    if Code.ensure_loaded?(config_module) and
         function_exported?(config_module, :embedding_config, 1) do
      not is_nil(config_module.embedding_config(model))
    else
      String.contains?(model, "embedding")
    end
  end

  defp embedding_model?(_), do: false

  defp config_module, do: Module.concat(Gemini, Config)

  defp config_available? do
    module = config_module()

    Code.ensure_loaded?(module) and
      function_exported?(module, :models_for, 1) and
      function_exported?(module, :current_api_type, 0)
  end

  defp models_for_current_api do
    module = config_module()
    module.models_for(module.current_api_type())
  end
end

# Only implement protocols if Gemini SDK is available
if Code.ensure_loaded?(Gemini) do
  defimpl Altar.AI.Generator, for: Altar.AI.Adapters.Gemini do
    alias Altar.AI.{Error, Response, Telemetry}
    alias Gemini.Types.Response.GenerateContentResponse

    def generate(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)
      {model_opt, effective_model} = resolve_generation_model(merged_opts)

      gemini_opts =
        merged_opts
        |> Keyword.delete(:model)
        |> maybe_put(:model, model_opt)
        |> normalize_gemini_opts()

      Telemetry.span(:text_gen, %{provider: :gemini, model: effective_model}, fn ->
        case Gemini.generate(prompt, gemini_opts) do
          {:ok, response} ->
            content = extract_content(response)
            tokens = extract_tokens(response)
            finish_reason = extract_finish_reason(response)

            {:ok,
             %Response{
               content: content,
               model: effective_model,
               provider: :gemini,
               finish_reason: finish_reason,
               tokens: tokens
             }}

          {:error, error} ->
            {:error, Error.from_gemini_error(error)}
        end
      end)
    end

    def stream(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)
      {model_opt, effective_model} = resolve_generation_model(merged_opts)

      gemini_opts =
        merged_opts
        |> Keyword.delete(:model)
        |> maybe_put(:model, model_opt)
        |> normalize_gemini_opts()

      Telemetry.span(:stream, %{provider: :gemini, model: effective_model}, fn ->
        case Gemini.stream_generate(prompt, gemini_opts) do
          {:ok, stream} ->
            {:ok, stream}

          {:error, error} ->
            {:error, Error.from_gemini_error(error)}
        end
      end)
    end

    defp resolve_generation_model(opts) do
      case Keyword.get(opts, :model) do
        nil ->
          default = Gemini.Config.default_model()
          {nil, default}

        model_key when is_atom(model_key) ->
          resolved =
            Gemini.Config.get_model(model_key,
              api: Gemini.Config.current_api_type(),
              strict: true
            )

          {resolved, resolved}

        model_name when is_binary(model_name) ->
          {model_name, model_name}
      end
    end

    defp normalize_gemini_opts(opts) do
      opts
      |> maybe_rename(:max_tokens, :max_output_tokens)
      |> maybe_rename(:system, :system_instruction)
      |> Keyword.put_new(:response_mime_type, "text/plain")
      |> Keyword.put_new(:response_modalities, [:text])
    end

    defp maybe_rename(opts, old_key, new_key) do
      case Keyword.pop(opts, old_key) do
        {nil, opts} -> opts
        {value, opts} -> Keyword.put_new(opts, new_key, value)
      end
    end

    defp maybe_put(opts, _key, nil), do: opts
    defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

    defp extract_content(%GenerateContentResponse{} = response) do
      case Gemini.extract_text(response) do
        {:ok, text} -> text
        {:error, _} -> ""
      end
    end

    defp extract_tokens(%GenerateContentResponse{} = response) do
      usage = GenerateContentResponse.token_usage(response)
      normalize_tokens(usage)
    end

    defp normalize_tokens(nil), do: %{prompt: 0, completion: 0, total: 0}

    defp normalize_tokens(usage) when is_map(usage) do
      %{
        prompt:
          Map.get(usage, :prompt_token_count) ||
            Map.get(usage, :input) ||
            Map.get(usage, "promptTokenCount") ||
            0,
        completion:
          Map.get(usage, :candidates_token_count) ||
            Map.get(usage, :output) ||
            Map.get(usage, "candidatesTokenCount") ||
            0,
        total:
          Map.get(usage, :total_token_count) ||
            Map.get(usage, "totalTokenCount") ||
            0
      }
    end

    defp extract_finish_reason(%GenerateContentResponse{} = response) do
      case GenerateContentResponse.finish_reason(response) do
        "STOP" -> :stop
        "MAX_TOKENS" -> :length
        "SAFETY" -> :stop
        _ -> :stop
      end
    end
  end

  defimpl Altar.AI.Embedder, for: Altar.AI.Adapters.Gemini do
    alias Altar.AI.{Error, Telemetry}

    alias Gemini.Types.Response.{
      BatchEmbedContentsResponse,
      ContentEmbedding,
      EmbedContentResponse
    }

    def embed(%{opts: opts}, text, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)
      {model_opt, effective_model} = resolve_embedding_model(merged_opts)
      dims = resolve_dimensions(merged_opts, effective_model)

      gemini_opts =
        merged_opts
        |> Keyword.delete(:model)
        |> Keyword.delete(:dimensions)
        |> Keyword.put(:output_dimensionality, dims)
        |> maybe_put(:model, model_opt)

      Telemetry.span(:embed, %{provider: :gemini, model: effective_model}, fn ->
        case Gemini.embed_content(text, gemini_opts) do
          {:ok, response} ->
            vector = extract_embedding(response)
            normalized_vector = maybe_normalize(vector, effective_model, dims)
            {:ok, normalized_vector}

          {:error, error} ->
            {:error, Error.from_gemini_error(error)}
        end
      end)
    end

    def batch_embed(%{opts: opts}, texts, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)
      {model_opt, effective_model} = resolve_embedding_model(merged_opts)
      dims = resolve_dimensions(merged_opts, effective_model)

      gemini_opts =
        merged_opts
        |> Keyword.delete(:model)
        |> Keyword.delete(:dimensions)
        |> Keyword.put(:output_dimensionality, dims)
        |> maybe_put(:model, model_opt)

      Telemetry.span(:batch_embed, %{provider: :gemini, count: length(texts)}, fn ->
        case batch_embed_contents(texts, gemini_opts) do
          {:ok, %BatchEmbedContentsResponse{} = response} ->
            extract_vectors(response, effective_model, dims)

          {:error, error} ->
            {:error, Error.from_gemini_error(error)}
        end
      end)
    end

    @spec batch_embed_contents([String.t()], keyword()) :: {:ok, term()} | {:error, term()}
    defp batch_embed_contents(texts, opts) do
      Gemini.batch_embed_contents(texts, opts)
    end

    defp resolve_embedding_model(opts) do
      case Keyword.get(opts, :model) do
        nil ->
          default = Gemini.Config.default_embedding_model()
          {nil, default}

        model_key when is_atom(model_key) ->
          resolved =
            Gemini.Config.get_model(model_key,
              api: Gemini.Config.current_api_type(),
              strict: true
            )

          {resolved, resolved}

        model_name when is_binary(model_name) ->
          {model_name, model_name}
      end
    end

    defp resolve_dimensions(opts, model) do
      case Keyword.get(opts, :dimensions) do
        nil ->
          Gemini.Config.default_embedding_dimensions(model) || 768

        dims ->
          dims
      end
    end

    defp extract_embedding(%EmbedContentResponse{embedding: embedding}),
      do: extract_embedding(embedding)

    defp extract_embedding(%ContentEmbedding{values: values}), do: values
    defp extract_embedding(%{embedding: %{values: values}}), do: values
    defp extract_embedding(%{embedding: values}) when is_list(values), do: values
    defp extract_embedding(%{values: values}) when is_list(values), do: values
    defp extract_embedding(values) when is_list(values), do: values
    defp extract_embedding(_), do: []

    defp extract_vectors(%BatchEmbedContentsResponse{embeddings: embeddings}, model, dims)
         when is_list(embeddings) do
      vectors =
        Enum.map(embeddings, fn emb ->
          vector = extract_embedding(emb)
          maybe_normalize(vector, model, dims)
        end)

      {:ok, vectors}
    end

    defp maybe_normalize(vector, model, dims) do
      if needs_normalization?(model, dims) do
        normalize(vector)
      else
        vector
      end
    end

    defp needs_normalization?(model, dims) do
      if function_exported?(Gemini.Config, :needs_normalization?, 2) do
        Gemini.Config.needs_normalization?(model, dims)
      else
        false
      end
    end

    defp normalize([_ | _] = vector) do
      magnitude = :math.sqrt(Enum.reduce(vector, 0, fn x, acc -> acc + x * x end))

      if magnitude > 0 do
        Enum.map(vector, fn x -> x / magnitude end)
      else
        vector
      end
    end

    defp normalize(vector), do: vector

    defp maybe_put(opts, _key, nil), do: opts
    defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
  end
end
