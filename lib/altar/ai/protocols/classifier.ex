defprotocol Altar.AI.Classifier do
  @moduledoc """
  Protocol for text classification.

  This protocol defines the interface for adapters that can classify
  text into predefined labels/categories.
  """

  @doc """
  Classify text into one of the provided labels.

  ## Parameters
    - adapter: The adapter struct implementing this protocol
    - text: The text to classify
    - labels: List of possible classification labels
    - opts: Optional keyword list of options

  ## Returns
    - `{:ok, classification}` - Success with classification result
    - `{:error, error}` - Error with details
  """
  @spec classify(t, String.t(), [String.t()], keyword()) ::
          {:ok, Altar.AI.Classification.t()} | {:error, Altar.AI.Error.t()}
  def classify(adapter, text, labels, opts \\ [])
end
