defmodule Altar.AI.Behaviours.Classify do
  @moduledoc """
  Behaviour for text classification capabilities.

  This behaviour defines a unified interface for classifying text into
  predefined categories or labels.

  ## Examples

      defmodule MyClassifier do
        @behaviour Altar.AI.Behaviours.Classify

        @impl true
        def classify(text, labels, opts) do
          # Implementation
          {:ok, %{
            label: "positive",
            confidence: 0.95,
            scores: %{
              "positive" => 0.95,
              "negative" => 0.03,
              "neutral" => 0.02
            }
          }}
        end
      end

  """

  alias Altar.AI.Error

  @type text :: String.t()
  @type label :: String.t()
  @type opts :: keyword()
  @type classification_result :: %{
          label: label(),
          confidence: float(),
          scores: %{label() => float()},
          metadata: map()
        }

  @doc """
  Classifies text into one of the provided labels.

  ## Parameters

    * `text` - The input text to classify
    * `labels` - List of possible classification labels
    * `opts` - Options including:
      * `:model` - Classification model to use (provider-specific)
      * `:multi_label` - Whether to allow multiple labels (default: false)
      * `:threshold` - Confidence threshold for classification

  ## Returns

    * `{:ok, result}` - Successfully classified text
    * `{:error, Error.t()}` - Classification failed

  """
  @callback classify(text(), [label()], opts()) ::
              {:ok, classification_result()} | {:error, Error.t()}
end
