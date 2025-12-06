defprotocol Altar.AI.Generator do
  @moduledoc """
  Protocol for text generation capabilities.

  This protocol defines the interface for adapters that can generate text
  from prompts. Implementations should handle model-specific details and
  return normalized responses.
  """

  @doc """
  Generate text from a prompt.

  ## Parameters
    - adapter: The adapter struct implementing this protocol
    - prompt: The text prompt to generate from
    - opts: Optional keyword list of options (model, temperature, max_tokens, etc.)

  ## Returns
    - `{:ok, response}` - Success with normalized response
    - `{:error, error}` - Error with details
  """
  @spec generate(t, String.t(), keyword()) ::
          {:ok, Altar.AI.Response.t()} | {:error, Altar.AI.Error.t()}
  def generate(adapter, prompt, opts \\ [])

  @doc """
  Stream text generation as it's produced.

  ## Parameters
    - adapter: The adapter struct implementing this protocol
    - prompt: The text prompt to generate from
    - opts: Optional keyword list of options

  ## Returns
    - `{:ok, stream}` - Success with enumerable stream of chunks
    - `{:error, error}` - Error with details
  """
  @spec stream(t, String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Altar.AI.Error.t()}
  def stream(adapter, prompt, opts \\ [])
end
