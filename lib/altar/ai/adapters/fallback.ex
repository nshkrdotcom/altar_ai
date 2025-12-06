defmodule Altar.AI.Adapters.Fallback do
  @moduledoc """
  Fallback adapter providing basic heuristic responses when no AI is available.

  This adapter uses simple pattern matching and templates to provide
  basic functionality without requiring any external AI services. It's
  useful as a last resort in composite chains or for testing.

  ## Configuration

      config :altar_ai,
        adapters: %{
          fallback: [
            templates: %{
              greeting: "Hello! How can I help you today?",
              farewell: "Goodbye! Have a great day!"
            }
          ]
        }

  ## Examples

      iex> Altar.AI.Adapters.Fallback.generate("hello")
      {:ok, %{content: "Hello! How can I help you today?", ...}}

      iex> Altar.AI.Adapters.Fallback.classify("I love this!", ["positive", "negative"])
      {:ok, %{label: "positive", confidence: 0.6, ...}}

  """

  @behaviour Altar.AI.Behaviours.TextGen
  @behaviour Altar.AI.Behaviours.Classify

  alias Altar.AI.Config

  @greeting_patterns ~w(hello hi hey greetings howdy)
  @farewell_patterns ~w(bye goodbye farewell later ciao)
  @positive_patterns ~w(good great excellent amazing wonderful love like happy)
  @negative_patterns ~w(bad terrible awful hate dislike sad angry)

  @impl true
  def generate(prompt, _opts \\ []) do
    response =
      cond do
        matches_pattern?(prompt, @greeting_patterns) ->
          get_template(:greeting, "Hello! How can I help you today?")

        matches_pattern?(prompt, @farewell_patterns) ->
          get_template(:farewell, "Goodbye! Have a great day!")

        true ->
          "I'm a simple fallback adapter. I can only respond to basic greetings and farewells. " <>
            "For advanced AI capabilities, please configure a real AI provider."
      end

    {:ok,
     %{
       content: response,
       model: "fallback-heuristic",
       tokens: %{
         prompt: count_tokens(prompt),
         completion: count_tokens(response),
         total: count_tokens(prompt) + count_tokens(response)
       },
       finish_reason: :stop,
       metadata: %{adapter: :fallback, heuristic: true}
     }}
  end

  @impl true
  def stream(prompt, opts \\ []) do
    # Convert generate response to a stream
    case generate(prompt, opts) do
      {:ok, response} ->
        stream =
          Stream.map([response], fn resp ->
            %{content: resp.content, delta: false, finish_reason: :stop}
          end)

        {:ok, stream}

      error ->
        error
    end
  end

  @impl true
  def classify(text, labels, _opts \\ []) do
    # Simple sentiment-based classification
    text_lower = String.downcase(text)

    positive_count = count_matches(text_lower, @positive_patterns)
    negative_count = count_matches(text_lower, @negative_patterns)

    # Determine which label to use based on heuristics
    {label, base_confidence} =
      cond do
        positive_count > negative_count and has_label?(labels, ["positive", "good", "happy"]) ->
          {find_label(labels, ["positive", "good", "happy"]), 0.6}

        negative_count > positive_count and has_label?(labels, ["negative", "bad", "sad"]) ->
          {find_label(labels, ["negative", "bad", "sad"]), 0.6}

        true ->
          # Default to first label with lower confidence
          {List.first(labels, "unknown"), 0.5}
      end

    # Generate scores for all labels
    scores = generate_scores(labels, label, base_confidence)

    {:ok,
     %{
       label: label,
       confidence: base_confidence,
       scores: scores,
       metadata: %{adapter: :fallback, heuristic: true}
     }}
  end

  # Private helpers

  defp matches_pattern?(text, patterns) do
    text_lower = String.downcase(text)
    Enum.any?(patterns, fn pattern -> String.contains?(text_lower, pattern) end)
  end

  defp count_matches(text, patterns) do
    Enum.count(patterns, fn pattern -> String.contains?(text, pattern) end)
  end

  defp has_label?(labels, candidates) do
    labels_lower = Enum.map(labels, &String.downcase/1)

    Enum.any?(candidates, fn candidate ->
      Enum.any?(labels_lower, fn label -> String.contains?(label, candidate) end)
    end)
  end

  defp find_label(labels, candidates) do
    labels_lower = Enum.map(labels, fn label -> {String.downcase(label), label} end)

    Enum.find_value(candidates, List.first(labels, "unknown"), fn candidate ->
      Enum.find_value(labels_lower, fn {lower, original} ->
        if String.contains?(lower, candidate), do: original
      end)
    end)
  end

  defp generate_scores(labels, selected_label, confidence) do
    total_labels = Enum.count(labels)
    remaining_confidence = 1.0 - confidence

    other_confidence =
      if total_labels > 1, do: remaining_confidence / (total_labels - 1), else: 0.0

    scores =
      labels
      |> Enum.map(fn label ->
        score = if label == selected_label, do: confidence, else: other_confidence
        {label, Float.round(score, 3)}
      end)
      |> Enum.into(%{})

    # Adjust the selected label's score to ensure sum is exactly 1.0
    sum = scores |> Map.values() |> Enum.sum()
    adjustment = 1.0 - sum

    if abs(adjustment) > 0.001 do
      Map.update!(scores, selected_label, &Float.round(&1 + adjustment, 3))
    else
      scores
    end
  end

  defp count_tokens(text) do
    # Very simple token counting (words + punctuation)
    text
    |> String.split(~r/\s+/)
    |> Enum.count()
  end

  defp get_template(key, default) do
    config = Config.get_adapter_config(:fallback)

    config
    |> Keyword.get(:templates, %{})
    |> Map.get(key, default)
  end
end
