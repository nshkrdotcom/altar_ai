defmodule Altar.AI.Behaviours.CodeGen do
  @moduledoc """
  Behaviour for code generation and explanation capabilities.

  This behaviour defines a unified interface for code-related AI operations
  including code generation, explanation, and analysis.

  ## Examples

      defmodule MyCodeGen do
        @behaviour Altar.AI.Behaviours.CodeGen

        @impl true
        def generate_code(prompt, opts) do
          # Implementation
          {:ok, %{
            code: "def hello, do: :world",
            language: "elixir",
            explanation: "A simple function...",
            model: "code-model"
          }}
        end

        @impl true
        def explain_code(code, opts) do
          # Implementation
          {:ok, %{
            explanation: "This code defines...",
            language: "elixir",
            complexity: :simple,
            model: "code-model"
          }}
        end
      end

  """

  alias Altar.AI.Error

  @type prompt :: String.t()
  @type code :: String.t()
  @type opts :: keyword()
  @type language :: String.t() | atom()
  @type code_response :: %{
          code: code(),
          language: language(),
          explanation: String.t() | nil,
          model: String.t(),
          metadata: map()
        }
  @type explanation_response :: %{
          explanation: String.t(),
          language: language() | nil,
          complexity: :simple | :moderate | :complex | nil,
          model: String.t(),
          metadata: map()
        }

  @doc """
  Generates code from a natural language prompt.

  ## Parameters

    * `prompt` - Natural language description of desired code
    * `opts` - Options including:
      * `:model` - Code generation model to use
      * `:language` - Target programming language
      * `:style` - Code style preferences
      * `:max_tokens` - Maximum tokens to generate
      * `:temperature` - Sampling temperature

  ## Returns

    * `{:ok, response}` - Successfully generated code
    * `{:error, Error.t()}` - Code generation failed

  """
  @callback generate_code(prompt(), opts()) :: {:ok, code_response()} | {:error, Error.t()}

  @doc """
  Explains existing code in natural language.

  ## Parameters

    * `code` - The code to explain
    * `opts` - Options including:
      * `:model` - Model to use for explanation
      * `:language` - Programming language of the code (auto-detected if not provided)
      * `:detail_level` - Level of detail (`:brief`, `:normal`, `:detailed`)

  ## Returns

    * `{:ok, response}` - Successfully explained code
    * `{:error, Error.t()}` - Code explanation failed

  """
  @callback explain_code(code(), opts()) ::
              {:ok, explanation_response()} | {:error, Error.t()}
end
