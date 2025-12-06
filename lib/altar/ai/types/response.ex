defmodule Altar.AI.Response do
  @moduledoc """
  Normalized response from any AI provider.

  This struct provides a unified representation of AI generation responses,
  abstracting away provider-specific details.
  """

  defstruct [
    :content,
    :model,
    :provider,
    :finish_reason,
    tokens: %{prompt: 0, completion: 0, total: 0},
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          content: String.t(),
          model: String.t(),
          provider: atom(),
          finish_reason: atom(),
          tokens: %{
            prompt: non_neg_integer(),
            completion: non_neg_integer(),
            total: non_neg_integer()
          },
          metadata: map()
        }

  @doc """
  Create a new response struct.

  ## Examples

      iex> Altar.AI.Response.new("Hello", model: "gpt-4", provider: :openai)
      %Altar.AI.Response{
        content: "Hello",
        model: "gpt-4",
        provider: :openai,
        finish_reason: :stop
      }
  """
  def new(content, opts \\ []) do
    %__MODULE__{
      content: content,
      model: Keyword.get(opts, :model),
      provider: Keyword.get(opts, :provider),
      finish_reason: Keyword.get(opts, :finish_reason, :stop),
      tokens: Keyword.get(opts, :tokens, %{prompt: 0, completion: 0, total: 0}),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
