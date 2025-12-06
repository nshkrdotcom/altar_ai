defmodule Altar.AI.Adapters.Fallback do
  @moduledoc """
  Heuristic fallback adapter when no AI providers are available.

  Provides simple rule-based responses without requiring any external APIs.
  Useful as a last resort in fallback chains.
  """

  defstruct opts: []

  @type t :: %__MODULE__{opts: keyword()}

  def new(opts \\ []), do: %__MODULE__{opts: opts}

  @doc "Always available."
  def available?, do: true
end

defimpl Altar.AI.Generator, for: Altar.AI.Adapters.Fallback do
  alias Altar.AI.{Response, Error}

  def generate(_adapter, prompt, _opts) do
    {:ok,
     %Response{
       content:
         "[Fallback] Unable to generate AI response for: #{String.slice(prompt, 0, 50)}...",
       provider: :fallback,
       model: "fallback",
       finish_reason: :fallback
     }}
  end

  def stream(_adapter, _prompt, _opts) do
    {:error, Error.new(:unsupported, "Fallback does not support streaming", provider: :fallback)}
  end
end

defimpl Altar.AI.Classifier, for: Altar.AI.Adapters.Fallback do
  alias Altar.AI.Classification

  def classify(_adapter, text, labels, _opts) do
    # Simple keyword-based classification
    text_lower = String.downcase(text)

    scores =
      Enum.map(labels, fn label ->
        label_lower = String.downcase(label)
        score = if String.contains?(text_lower, label_lower), do: 0.8, else: 0.2
        {label, score}
      end)

    {best_label, best_score} = Enum.max_by(scores, fn {_, s} -> s end)

    {:ok,
     %Classification{
       label: best_label,
       confidence: best_score,
       all_scores: Map.new(scores)
     }}
  end
end
