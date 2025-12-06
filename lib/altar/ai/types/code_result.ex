defmodule Altar.AI.CodeResult do
  @moduledoc """
  Result of a code generation operation.

  Contains the generated code along with optional metadata
  like language, explanation, and tests.
  """

  defstruct [:code, :language, :explanation, :tests, metadata: %{}]

  @type t :: %__MODULE__{
          code: String.t(),
          language: String.t() | nil,
          explanation: String.t() | nil,
          tests: String.t() | nil,
          metadata: map()
        }

  @doc """
  Create a new code result.

  ## Examples

      iex> Altar.AI.CodeResult.new("def hello, do: :world", language: "elixir")
      %Altar.AI.CodeResult{
        code: "def hello, do: :world",
        language: "elixir"
      }
  """
  def new(code, opts \\ []) do
    %__MODULE__{
      code: code,
      language: Keyword.get(opts, :language),
      explanation: Keyword.get(opts, :explanation),
      tests: Keyword.get(opts, :tests),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
