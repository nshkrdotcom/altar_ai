defmodule Altar.AI do
  @moduledoc """
  Unified AI adapter foundation for Elixir.

  Provides protocol-based abstractions for AI operations with adapters
  for gemini_ex, claude_agent_sdk, and codex_sdk.

  ## Quick Start

      # Create an adapter
      adapter = Altar.AI.Adapters.Gemini.new()

      # Or use composite for fallback
      adapter = Altar.AI.Adapters.Composite.default()

      # Generate text
      {:ok, response} = Altar.AI.generate(adapter, "Hello, world!")

      # Check capabilities
      Altar.AI.capabilities(adapter)
      #=> %{generate: true, embed: true, classify: false, ...}

  ## Architecture

  Altar.AI uses **protocols** instead of behaviours for maximum flexibility:

  - `Altar.AI.Generator` - Text generation and streaming
  - `Altar.AI.Embedder` - Vector embeddings
  - `Altar.AI.Classifier` - Text classification
  - `Altar.AI.CodeGenerator` - Code generation and explanation

  This allows:
  - Runtime capability detection
  - Cleaner composite adapter implementation
  - Dispatching on adapter structs

  ## Adapters

  Available adapters (when SDKs are installed):

  - `Altar.AI.Adapters.Gemini` - Google Gemini (gemini_ex)
  - `Altar.AI.Adapters.Claude` - Anthropic Claude (claude_agent_sdk)
  - `Altar.AI.Adapters.Codex` - OpenAI (codex_sdk)
  - `Altar.AI.Adapters.Composite` - Fallback chain
  - `Altar.AI.Adapters.Mock` - Testing
  - `Altar.AI.Adapters.Fallback` - Heuristic fallback

  ## Examples

      # Use a specific adapter
      gemini = Altar.AI.Adapters.Gemini.new(api_key: "...")
      {:ok, response} = Altar.AI.generate(gemini, "Explain protocols")

      # Use composite with automatic fallback
      composite = Altar.AI.Adapters.Composite.default()
      {:ok, response} = Altar.AI.generate(composite, "Hello")

      # Check what an adapter can do
      Altar.AI.supports?(gemini, :embed)  #=> true
      Altar.AI.supports?(gemini, :classify)  #=> false

      # Get embeddings
      {:ok, vector} = Altar.AI.embed(gemini, "semantic search")

      # Classification (with fallback adapter)
      fallback = Altar.AI.Adapters.Fallback.new()
      {:ok, classification} = Altar.AI.classify(fallback, "Great!", ["positive", "negative"])
  """

  alias Altar.AI.{Generator, Embedder, Classifier, CodeGenerator, Capabilities}

  # Delegate to protocols
  defdelegate generate(adapter, prompt, opts \\ []), to: Generator
  defdelegate stream(adapter, prompt, opts \\ []), to: Generator
  defdelegate embed(adapter, text, opts \\ []), to: Embedder
  defdelegate batch_embed(adapter, texts, opts \\ []), to: Embedder
  defdelegate classify(adapter, text, labels, opts \\ []), to: Classifier
  defdelegate generate_code(adapter, prompt, opts \\ []), to: CodeGenerator
  defdelegate explain_code(adapter, code, opts \\ []), to: CodeGenerator

  # Capability detection
  defdelegate capabilities(adapter), to: Capabilities
  defdelegate supports?(adapter, capability), to: Capabilities

  @doc """
  Get default adapter based on available SDKs.

  Returns a Composite adapter with automatic fallback chain.

  ## Examples

      iex> adapter = Altar.AI.default_adapter()
      iex> Altar.AI.capabilities(adapter)
  """
  def default_adapter do
    Altar.AI.Adapters.Composite.default()
  end

  @doc """
  List all available adapters (SDKs that are installed).

  ## Examples

      iex> Altar.AI.available_adapters()
      [Altar.AI.Adapters.Gemini, Altar.AI.Adapters.Fallback]
  """
  def available_adapters do
    [
      Altar.AI.Adapters.Gemini,
      Altar.AI.Adapters.Claude,
      Altar.AI.Adapters.Codex,
      Altar.AI.Adapters.Fallback,
      Altar.AI.Adapters.Mock
    ]
    |> Enum.filter(& &1.available?())
  end
end
