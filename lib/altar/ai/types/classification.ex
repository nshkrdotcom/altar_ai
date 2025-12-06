defmodule Altar.AI.Classification do
  @moduledoc """
  Classification result with confidence scores.

  Represents the result of a text classification operation,
  including the selected label and confidence scores for all labels.
  """

  defstruct [:label, :confidence, :all_scores]

  @type t :: %__MODULE__{
          label: String.t(),
          confidence: float(),
          all_scores: %{String.t() => float()}
        }

  @doc """
  Create a new classification result.

  ## Examples

      iex> Altar.AI.Classification.new("positive", 0.95, %{"positive" => 0.95, "negative" => 0.05})
      %Altar.AI.Classification{
        label: "positive",
        confidence: 0.95,
        all_scores: %{"positive" => 0.95, "negative" => 0.05}
      }
  """
  def new(label, confidence, all_scores \\ %{}) do
    %__MODULE__{
      label: label,
      confidence: confidence,
      all_scores: all_scores
    }
  end

  @doc """
  Create a classification from a list of label-score tuples.

  ## Examples

      iex> Altar.AI.Classification.from_scores([{"positive", 0.9}, {"negative", 0.1}])
      %Altar.AI.Classification{
        label: "positive",
        confidence: 0.9,
        all_scores: %{"positive" => 0.9, "negative" => 0.1}
      }
  """
  def from_scores(scores) when is_list(scores) do
    all_scores = Map.new(scores)
    {label, confidence} = Enum.max_by(scores, fn {_label, score} -> score end)

    %__MODULE__{
      label: label,
      confidence: confidence,
      all_scores: all_scores
    }
  end
end
