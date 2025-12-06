defprotocol Altar.AI.CodeGenerator do
  @moduledoc """
  Protocol for code generation and analysis.

  This protocol defines the interface for adapters specialized in
  code-related tasks like generation, explanation, and review.
  """

  @doc """
  Generate code from a natural language prompt.

  ## Parameters
    - adapter: The adapter struct implementing this protocol
    - prompt: Description of the code to generate
    - opts: Optional keyword list of options (language, style, etc.)

  ## Returns
    - `{:ok, code_result}` - Success with generated code
    - `{:error, error}` - Error with details
  """
  @spec generate_code(t, String.t(), keyword()) ::
          {:ok, Altar.AI.CodeResult.t()} | {:error, Altar.AI.Error.t()}
  def generate_code(adapter, prompt, opts \\ [])

  @doc """
  Explain what a piece of code does.

  ## Parameters
    - adapter: The adapter struct implementing this protocol
    - code: The code to explain
    - opts: Optional keyword list of options

  ## Returns
    - `{:ok, explanation}` - Success with code explanation
    - `{:error, error}` - Error with details
  """
  @spec explain_code(t, String.t(), keyword()) ::
          {:ok, String.t()} | {:error, Altar.AI.Error.t()}
  def explain_code(adapter, code, opts \\ [])
end
