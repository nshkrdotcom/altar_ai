defmodule Altar.AI do
  @moduledoc """
  Unified AI adapter foundation for Elixir.

  Altar.AI provides a consistent interface for working with multiple AI
  providers including Gemini, Claude, and Codex. It offers:

  - Unified behaviours for text generation, embeddings, classification, and code generation
  - Adapter pattern for easy provider switching
  - Composite adapter with automatic fallback
  - Comprehensive telemetry and error handling
  - Testing utilities with mock adapter

  ## Quick Start

      # Configure your adapter
      config :altar_ai,
        default_adapter: Altar.AI.Adapters.Gemini,
        adapters: %{
          gemini: [
            api_key: {:system, "GEMINI_API_KEY"},
            model: "gemini-2.0-flash-exp"
          ]
        }

      # Generate text
      {:ok, response} = Altar.AI.generate("Hello, world!")
      IO.puts(response.content)

      # Stream responses
      {:ok, stream} = Altar.AI.stream("Tell me a story")
      Enum.each(stream, fn chunk -> IO.write(chunk.content) end)

      # Generate embeddings
      {:ok, embedding} = Altar.AI.embed("semantic search")
      vector = embedding.vector

      # Classify text
      {:ok, result} = Altar.AI.classify("I love this!", ["positive", "negative"])
      IO.puts(result.label)

      # Generate code
      {:ok, code} = Altar.AI.generate_code("fibonacci function in elixir")
      IO.puts(code.code)

  ## Adapters

  Use a specific adapter directly:

      Altar.AI.Adapters.Gemini.generate("Hello")
      Altar.AI.Adapters.Claude.generate("Hello")
      Altar.AI.Adapters.Codex.generate_code("create a function")

  Or configure a composite adapter with fallbacks:

      config :altar_ai,
        default_adapter: Altar.AI.Adapters.Composite,
        adapters: %{
          composite: [
            providers: [
              {Altar.AI.Adapters.Gemini, []},
              {Altar.AI.Adapters.Claude, []},
              {Altar.AI.Adapters.Fallback, []}
            ]
          ]
        }

  """

  alias Altar.AI.{Config, Telemetry}

  @doc """
  Generates text using the configured default adapter.

  ## Parameters

    * `prompt` - Text prompt
    * `opts` - Options (adapter-specific)

  ## Examples

      {:ok, response} = Altar.AI.generate("What is Elixir?")
      IO.puts(response.content)

  """
  @spec generate(String.t(), keyword()) ::
          {:ok, map()} | {:error, Altar.AI.Error.t()}
  def generate(prompt, opts \\ []) do
    adapter = get_adapter(opts)

    Telemetry.span(:text_gen, %{provider: adapter}, fn ->
      adapter.generate(prompt, opts)
    end)
  end

  @doc """
  Streams text generation using the configured default adapter.

  ## Parameters

    * `prompt` - Text prompt
    * `opts` - Options (adapter-specific)

  ## Examples

      {:ok, stream} = Altar.AI.stream("Tell me a story")
      Enum.each(stream, fn chunk -> IO.write(chunk.content) end)

  """
  @spec stream(String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Altar.AI.Error.t()}
  def stream(prompt, opts \\ []) do
    adapter = get_adapter(opts)

    Telemetry.span(:text_gen, %{provider: adapter, streaming: true}, fn ->
      adapter.stream(prompt, opts)
    end)
  end

  @doc """
  Generates an embedding vector using the configured default adapter.

  ## Parameters

    * `text` - Text to embed
    * `opts` - Options (adapter-specific)

  ## Examples

      {:ok, embedding} = Altar.AI.embed("semantic search query")
      vector = embedding.vector

  """
  @spec embed(String.t(), keyword()) ::
          {:ok, map()} | {:error, Altar.AI.Error.t()}
  def embed(text, opts \\ []) do
    adapter = get_adapter(opts)

    Telemetry.span(:embed, %{provider: adapter}, fn ->
      adapter.embed(text, opts)
    end)
  end

  @doc """
  Generates embedding vectors for multiple texts using the configured default adapter.

  ## Parameters

    * `texts` - List of texts to embed
    * `opts` - Options (adapter-specific)

  ## Examples

      {:ok, embeddings} = Altar.AI.batch_embed(["query 1", "query 2"])
      vectors = embeddings.vectors

  """
  @spec batch_embed([String.t()], keyword()) ::
          {:ok, map()} | {:error, Altar.AI.Error.t()}
  def batch_embed(texts, opts \\ []) do
    adapter = get_adapter(opts)

    Telemetry.span(:embed, %{provider: adapter, batch: true}, fn ->
      adapter.batch_embed(texts, opts)
    end)
  end

  @doc """
  Classifies text using the configured default adapter.

  ## Parameters

    * `text` - Text to classify
    * `labels` - Possible classification labels
    * `opts` - Options (adapter-specific)

  ## Examples

      {:ok, result} = Altar.AI.classify("I love this product!", ["positive", "negative", "neutral"])
      IO.puts("Label: \#{result.label}, Confidence: \#{result.confidence}")

  """
  @spec classify(String.t(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, Altar.AI.Error.t()}
  def classify(text, labels, opts \\ []) do
    adapter = get_adapter(opts)

    Telemetry.span(:classify, %{provider: adapter}, fn ->
      adapter.classify(text, labels, opts)
    end)
  end

  @doc """
  Generates code using the configured default adapter.

  ## Parameters

    * `prompt` - Natural language description of desired code
    * `opts` - Options (adapter-specific, may include `:language`)

  ## Examples

      {:ok, code} = Altar.AI.generate_code("fibonacci function", language: "elixir")
      IO.puts(code.code)

  """
  @spec generate_code(String.t(), keyword()) ::
          {:ok, map()} | {:error, Altar.AI.Error.t()}
  def generate_code(prompt, opts \\ []) do
    adapter = get_adapter(opts)

    Telemetry.span(:code_gen, %{provider: adapter}, fn ->
      adapter.generate_code(prompt, opts)
    end)
  end

  @doc """
  Explains code using the configured default adapter.

  ## Parameters

    * `code` - Code to explain
    * `opts` - Options (adapter-specific, may include `:language`, `:detail_level`)

  ## Examples

      {:ok, explanation} = Altar.AI.explain_code("def fib(0), do: 0", language: "elixir")
      IO.puts(explanation.explanation)

  """
  @spec explain_code(String.t(), keyword()) ::
          {:ok, map()} | {:error, Altar.AI.Error.t()}
  def explain_code(code, opts \\ []) do
    adapter = get_adapter(opts)

    Telemetry.span(:code_gen, %{provider: adapter, operation: :explain}, fn ->
      adapter.explain_code(code, opts)
    end)
  end

  # Private helpers

  defp get_adapter(opts) do
    Keyword.get(opts, :adapter, Config.get_adapter())
  end
end
