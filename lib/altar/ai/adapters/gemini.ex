defmodule Altar.AI.Adapters.Gemini do
  @moduledoc """
  Gemini adapter for Altar.AI.

  This adapter wraps the `gemini` package to provide TextGen and Embed
  capabilities through Google's Gemini API.

  ## Configuration

      config :altar_ai,
        adapters: %{
          gemini: [
            api_key: {:system, "GEMINI_API_KEY"},
            model: "gemini-2.0-flash-exp"
          ]
        }

  ## Examples

      iex> Altar.AI.Adapters.Gemini.generate("Hello", model: "gemini-pro")
      {:ok, %{content: "Hi there!", model: "gemini-pro", ...}}

  """

  @behaviour Altar.AI.Behaviours.TextGen
  @behaviour Altar.AI.Behaviours.Embed

  alias Altar.AI.{Config, Error, Response}

  @impl true
  def generate(prompt, opts \\ []) do
    if gemini_available?() do
      generate_with_gemini(prompt, opts)
    else
      {:error,
       Error.new(
         :not_found,
         "Gemini package not available. Add {:gemini, \"~> 0.1.0\"} to your deps.",
         :gemini
       )}
    end
  end

  @impl true
  def stream(prompt, opts \\ []) do
    if gemini_available?() do
      stream_with_gemini(prompt, opts)
    else
      {:error,
       Error.new(
         :not_found,
         "Gemini package not available. Add {:gemini, \"~> 0.1.0\"} to your deps.",
         :gemini
       )}
    end
  end

  @impl true
  def embed(text, opts \\ []) do
    if gemini_available?() do
      embed_with_gemini(text, opts)
    else
      {:error,
       Error.new(
         :not_found,
         "Gemini package not available. Add {:gemini, \"~> 0.1.0\"} to your deps.",
         :gemini
       )}
    end
  end

  @impl true
  def batch_embed(texts, opts \\ []) do
    if gemini_available?() do
      batch_embed_with_gemini(texts, opts)
    else
      {:error,
       Error.new(
         :not_found,
         "Gemini package not available. Add {:gemini, \"~> 0.1.0\"} to your deps.",
         :gemini
       )}
    end
  end

  # Private implementation

  defp gemini_available? do
    Code.ensure_loaded?(Gemini)
  end

  defp generate_with_gemini(prompt, opts) do
    config = Config.get_adapter_config(:gemini)
    model = Keyword.get(opts, :model, Keyword.get(config, :model, "gemini-2.0-flash-exp"))

    request_opts = build_request_opts(config, opts)

    case Gemini.generate_content(model, prompt, request_opts) do
      {:ok, response} ->
        {:ok, normalize_generate_response(response, model)}

      {:error, error} ->
        {:error, normalize_error(error)}
    end
  end

  defp stream_with_gemini(prompt, opts) do
    config = Config.get_adapter_config(:gemini)
    model = Keyword.get(opts, :model, Keyword.get(config, :model, "gemini-2.0-flash-exp"))

    request_opts = build_request_opts(config, opts)

    case Gemini.stream_generate_content(model, prompt, request_opts) do
      {:ok, stream} ->
        normalized_stream =
          Stream.map(stream, fn chunk ->
            %{
              content: Response.extract_content(chunk),
              delta: true,
              finish_reason: nil
            }
          end)

        {:ok, normalized_stream}

      {:error, error} ->
        {:error, normalize_error(error)}
    end
  end

  defp embed_with_gemini(text, opts) do
    config = Config.get_adapter_config(:gemini)
    model = Keyword.get(opts, :model, Keyword.get(config, :embedding_model, "text-embedding-004"))

    request_opts = build_request_opts(config, opts)

    case Gemini.embed_content(model, text, request_opts) do
      {:ok, response} ->
        {:ok, normalize_embed_response(response, model)}

      {:error, error} ->
        {:error, normalize_error(error)}
    end
  end

  defp batch_embed_with_gemini(texts, opts) do
    config = Config.get_adapter_config(:gemini)
    model = Keyword.get(opts, :model, Keyword.get(config, :embedding_model, "text-embedding-004"))

    request_opts = build_request_opts(config, opts)

    case Gemini.batch_embed_contents(model, texts, request_opts) do
      {:ok, response} ->
        {:ok, normalize_batch_embed_response(response, model)}

      {:error, error} ->
        {:error, normalize_error(error)}
    end
  end

  defp build_request_opts(config, opts) do
    base_opts = [
      api_key: Keyword.get(config, :api_key)
    ]

    # Merge in supported options
    opts
    |> Keyword.take([:temperature, :max_tokens, :top_p, :stop, :system])
    |> Keyword.merge(base_opts)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp normalize_generate_response(response, model) do
    %{
      content: Response.extract_content(response),
      model: model,
      tokens: Response.normalize_tokens(Map.get(response, :usage, %{})),
      finish_reason: Response.normalize_finish_reason(Map.get(response, :finish_reason)),
      metadata: Response.extract_metadata(response)
    }
  end

  defp normalize_embed_response(response, model) do
    %{
      vector: Map.get(response, :embedding, []),
      model: model,
      dimensions: length(Map.get(response, :embedding, [])),
      metadata: Response.extract_metadata(response)
    }
  end

  defp normalize_batch_embed_response(response, model) do
    embeddings = Map.get(response, :embeddings, [])
    dimensions = embeddings |> List.first([]) |> length()

    %{
      vectors: embeddings,
      model: model,
      dimensions: dimensions,
      metadata: Response.extract_metadata(response)
    }
  end

  defp normalize_error(error) when is_binary(error) do
    Error.new(:api_error, error, :gemini)
  end

  defp normalize_error(%{message: message}) do
    Error.new(:api_error, message, :gemini)
  end

  defp normalize_error(error) do
    Error.new(:api_error, inspect(error), :gemini)
  end
end
