defmodule Altar.AI.Behaviours.TextGen do
  @moduledoc """
  Behaviour for text generation capabilities.

  This behaviour defines a unified interface for text generation across
  different AI providers. Implementations must normalize responses to
  a consistent format.

  ## Normalized Response Format

  The response map must include:

    * `:content` - Generated text content
    * `:model` - Model identifier used for generation
    * `:tokens` - Token usage information (map with `:prompt`, `:completion`, `:total`)
    * `:finish_reason` - Why generation stopped (`:stop`, `:length`, `:error`)
    * `:metadata` - Provider-specific metadata (optional)

  ## Examples

      defmodule MyAdapter do
        @behaviour Altar.AI.Behaviours.TextGen

        @impl true
        def generate(prompt, opts) do
          # Implementation
          {:ok, %{
            content: "Generated text",
            model: "my-model",
            tokens: %{prompt: 10, completion: 20, total: 30},
            finish_reason: :stop
          }}
        end

        @impl true
        def stream(prompt, opts) do
          stream = Stream.map(["chunk1", "chunk2"], fn chunk ->
            %{content: chunk, delta: true}
          end)
          {:ok, stream}
        end
      end

  """

  alias Altar.AI.Error

  @type prompt :: String.t()
  @type opts :: keyword()
  @type response :: %{
          content: String.t(),
          model: String.t(),
          tokens: %{
            prompt: non_neg_integer(),
            completion: non_neg_integer(),
            total: non_neg_integer()
          },
          finish_reason: :stop | :length | :error | atom(),
          metadata: map()
        }
  @type stream_chunk :: %{
          content: String.t(),
          delta: boolean(),
          finish_reason: atom() | nil
        }

  @doc """
  Generates text from a prompt.

  ## Parameters

    * `prompt` - The input prompt string
    * `opts` - Options including:
      * `:model` - Model to use (provider-specific)
      * `:temperature` - Sampling temperature (0.0-2.0)
      * `:max_tokens` - Maximum tokens to generate
      * `:top_p` - Nucleus sampling parameter
      * `:stop` - Stop sequences (list of strings)
      * `:system` - System prompt/context

  ## Returns

    * `{:ok, response}` - Successfully generated text
    * `{:error, Error.t()}` - Generation failed

  """
  @callback generate(prompt(), opts()) :: {:ok, response()} | {:error, Error.t()}

  @doc """
  Streams text generation from a prompt.

  Returns an enumerable that yields chunks of generated text as they
  become available. Each chunk is a map with `:content` and optionally
  `:delta` (true if this is a delta update) and `:finish_reason`.

  ## Parameters

    * `prompt` - The input prompt string
    * `opts` - Same options as `generate/2`

  ## Returns

    * `{:ok, stream}` - Stream of text chunks
    * `{:error, Error.t()}` - Stream creation failed

  """
  @callback stream(prompt(), opts()) :: {:ok, Enumerable.t(stream_chunk())} | {:error, Error.t()}
end
