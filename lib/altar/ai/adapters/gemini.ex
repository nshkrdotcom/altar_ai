defmodule Altar.AI.Adapters.Gemini do
  @moduledoc """
  Gemini adapter wrapping gemini_ex.

  Provides protocol implementations for Gemini AI capabilities including
  text generation and embeddings.
  """

  defstruct opts: []

  @type t :: %__MODULE__{opts: keyword()}

  @doc """
  Create a new Gemini adapter.

  ## Options
    - `:api_key` - Gemini API key (defaults to GEMINI_API_KEY env var)
    - `:model` - Default model to use (e.g., "gemini-pro")
    - Other options passed through to Gemini SDK

  ## Examples

      iex> Altar.AI.Adapters.Gemini.new(model: "gemini-pro")
      %Altar.AI.Adapters.Gemini{opts: [model: "gemini-pro"]}
  """
  def new(opts \\ []), do: %__MODULE__{opts: opts}

  # Check if SDK available at compile time
  @gemini_available Code.ensure_loaded?(Gemini)

  @doc """
  Check if the Gemini SDK is available.
  """
  def available?, do: @gemini_available
end

# Only implement protocols if Gemini SDK is available
if Code.ensure_loaded?(Gemini) do
  defimpl Altar.AI.Generator, for: Altar.AI.Adapters.Gemini do
    alias Altar.AI.{Response, Error, Telemetry}

    def generate(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)

      Telemetry.span(:generate, %{provider: :gemini, prompt_length: String.length(prompt)}, fn ->
        model = merged_opts[:model] || "gemini-pro"

        case Gemini.generate_content(model, prompt, merged_opts) do
          {:ok, response} ->
            {:ok,
             %Response{
               content: extract_content(response),
               model: model,
               provider: :gemini,
               finish_reason: :stop,
               tokens: extract_tokens(response)
             }}

          {:error, error} ->
            {:error, Error.from_gemini_error(error)}
        end
      end)
    end

    def stream(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)

      Telemetry.span(:stream, %{provider: :gemini, prompt_length: String.length(prompt)}, fn ->
        model = merged_opts[:model] || "gemini-pro"

        case Gemini.stream_generate_content(model, prompt, merged_opts) do
          {:ok, stream} ->
            {:ok, stream}

          {:error, error} ->
            {:error, Error.from_gemini_error(error)}
        end
      end)
    end

    defp extract_content(response) do
      case response do
        %{candidates: [%{content: %{parts: [%{text: text} | _]}} | _]} -> text
        %{text: text} -> text
        _ -> ""
      end
    end

    defp extract_tokens(response) do
      case response do
        %{usage_metadata: usage} ->
          %{
            prompt: Map.get(usage, :prompt_token_count, 0),
            completion: Map.get(usage, :candidates_token_count, 0),
            total: Map.get(usage, :total_token_count, 0)
          }

        _ ->
          %{prompt: 0, completion: 0, total: 0}
      end
    end
  end

  defimpl Altar.AI.Embedder, for: Altar.AI.Adapters.Gemini do
    alias Altar.AI.{Error, Telemetry}

    def embed(%{opts: opts}, text, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)

      Telemetry.span(:embed, %{provider: :gemini}, fn ->
        model = merged_opts[:model] || "text-embedding-004"

        case Gemini.embed_content(model, text, merged_opts) do
          {:ok, response} ->
            extract_vector(response)

          {:error, error} ->
            {:error, Error.from_gemini_error(error)}
        end
      end)
    end

    def batch_embed(%{opts: opts}, texts, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)

      Telemetry.span(:batch_embed, %{provider: :gemini, count: length(texts)}, fn ->
        model = merged_opts[:model] || "text-embedding-004"

        case Gemini.batch_embed_contents(model, texts, merged_opts) do
          {:ok, response} ->
            extract_vectors(response)

          {:error, error} ->
            {:error, Error.from_gemini_error(error)}
        end
      end)
    end

    # Extract embedding vector from Gemini response
    defp extract_vector(%{embedding: %{values: values}}), do: {:ok, values}
    defp extract_vector(%{embedding: values}) when is_list(values), do: {:ok, values}

    defp extract_vector(_),
      do: {:error, Error.new(:invalid_request, "Invalid embedding response", provider: :gemini)}

    # Extract multiple embedding vectors from batch response
    defp extract_vectors(%{embeddings: embeddings}) when is_list(embeddings) do
      vectors =
        Enum.map(embeddings, fn
          %{values: values} -> values
          values when is_list(values) -> values
          _ -> []
        end)

      {:ok, vectors}
    end

    defp extract_vectors(_),
      do:
        {:error,
         Error.new(:invalid_request, "Invalid batch embedding response", provider: :gemini)}
  end
end
