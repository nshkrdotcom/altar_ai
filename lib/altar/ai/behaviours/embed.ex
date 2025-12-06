defmodule Altar.AI.Behaviours.Embed do
  @moduledoc """
  Behaviour for text embedding capabilities.

  This behaviour defines a unified interface for generating vector embeddings
  from text across different AI providers.

  ## Examples

      defmodule MyEmbedAdapter do
        @behaviour Altar.AI.Behaviours.Embed

        @impl true
        def embed(text, opts) do
          # Implementation
          {:ok, %{
            vector: [0.1, 0.2, 0.3, ...],
            model: "embedding-model",
            dimensions: 768
          }}
        end

        @impl true
        def batch_embed(texts, opts) do
          # Implementation
          {:ok, %{
            vectors: [[0.1, 0.2, ...], [0.3, 0.4, ...]],
            model: "embedding-model",
            dimensions: 768
          }}
        end
      end

  """

  alias Altar.AI.Error

  @type text :: String.t()
  @type opts :: keyword()
  @type vector :: [float()]
  @type embed_response :: %{
          vector: vector(),
          model: String.t(),
          dimensions: pos_integer(),
          metadata: map()
        }
  @type batch_response :: %{
          vectors: [vector()],
          model: String.t(),
          dimensions: pos_integer(),
          metadata: map()
        }

  @doc """
  Generates an embedding vector for a single text input.

  ## Parameters

    * `text` - The input text to embed
    * `opts` - Options including:
      * `:model` - Embedding model to use (provider-specific)
      * `:task_type` - Task type hint (e.g., `:retrieval_query`, `:retrieval_document`)
      * `:dimensions` - Desired output dimensions (if supported)

  ## Returns

    * `{:ok, response}` - Successfully generated embedding
    * `{:error, Error.t()}` - Embedding generation failed

  """
  @callback embed(text(), opts()) :: {:ok, embed_response()} | {:error, Error.t()}

  @doc """
  Generates embedding vectors for multiple text inputs in a batch.

  This is more efficient than calling `embed/2` multiple times when
  you have multiple texts to embed.

  ## Parameters

    * `texts` - List of input texts to embed
    * `opts` - Same options as `embed/2`

  ## Returns

    * `{:ok, response}` - Successfully generated embeddings (vectors in same order as input)
    * `{:error, Error.t()}` - Batch embedding failed

  """
  @callback batch_embed([text()], opts()) :: {:ok, batch_response()} | {:error, Error.t()}
end
