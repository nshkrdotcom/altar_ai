defprotocol Altar.AI.Embedder do
  @moduledoc """
  Protocol for embedding generation.

  This protocol defines the interface for adapters that can generate
  vector embeddings from text. Useful for semantic search, clustering,
  and similarity calculations.
  """

  @doc """
  Generate an embedding vector for a single text.

  ## Parameters
    - adapter: The adapter struct implementing this protocol
    - text: The text to embed
    - opts: Optional keyword list of options (model, dimensions, etc.)

  ## Returns
    - `{:ok, vector}` - Success with embedding vector (list of floats)
    - `{:error, error}` - Error with details
  """
  @spec embed(t, String.t(), keyword()) ::
          {:ok, [float()]} | {:error, Altar.AI.Error.t()}
  def embed(adapter, text, opts \\ [])

  @doc """
  Generate embedding vectors for multiple texts in a batch.

  More efficient than calling embed/3 multiple times.

  ## Parameters
    - adapter: The adapter struct implementing this protocol
    - texts: List of texts to embed
    - opts: Optional keyword list of options

  ## Returns
    - `{:ok, vectors}` - Success with list of embedding vectors
    - `{:error, error}` - Error with details
  """
  @spec batch_embed(t, [String.t()], keyword()) ::
          {:ok, [[float()]]} | {:error, Altar.AI.Error.t()}
  def batch_embed(adapter, texts, opts \\ [])
end
