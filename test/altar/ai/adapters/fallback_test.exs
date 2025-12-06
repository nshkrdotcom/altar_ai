defmodule Altar.AI.Adapters.FallbackTest do
  use ExUnit.Case, async: true

  alias Altar.AI.Adapters.Fallback

  describe "generate/2" do
    test "recognizes greetings" do
      {:ok, response} = Fallback.generate("hello there")

      assert response.content =~ ~r/hello/i
      assert response.model == "fallback-heuristic"
      assert response.finish_reason == :stop
    end

    test "recognizes farewells" do
      {:ok, response} = Fallback.generate("goodbye friend")

      assert response.content =~ ~r/goodbye/i
      assert response.model == "fallback-heuristic"
    end

    test "returns generic response for unknown input" do
      {:ok, response} = Fallback.generate("some random text")

      assert response.content =~ "fallback adapter"
      assert response.metadata.heuristic == true
    end

    test "counts tokens" do
      {:ok, response} = Fallback.generate("hello world")

      assert response.tokens.prompt > 0
      assert response.tokens.completion > 0
      assert response.tokens.total == response.tokens.prompt + response.tokens.completion
    end
  end

  describe "stream/2" do
    test "converts response to stream" do
      {:ok, stream} = Fallback.stream("hello")

      chunks = Enum.to_list(stream)
      assert length(chunks) > 0

      chunk = List.first(chunks)
      assert %{content: _, delta: false, finish_reason: :stop} = chunk
    end
  end

  describe "classify/3" do
    test "detects positive sentiment" do
      text = "I love this wonderful amazing product!"
      labels = ["positive", "negative", "neutral"]

      {:ok, result} = Fallback.classify(text, labels)

      assert result.label == "positive"
      assert result.confidence > 0.0
      assert Map.has_key?(result.scores, "positive")
      assert Map.has_key?(result.scores, "negative")
      assert Map.has_key?(result.scores, "neutral")
    end

    test "detects negative sentiment" do
      text = "This is terrible, I hate it, so bad and awful"
      labels = ["positive", "negative", "neutral"]

      {:ok, result} = Fallback.classify(text, labels)

      assert result.label == "negative"
      assert result.confidence > 0.0
    end

    test "defaults to first label for neutral text" do
      text = "The sky is blue"
      labels = ["happy", "sad"]

      {:ok, result} = Fallback.classify(text, labels)

      assert result.label == "happy"
      assert result.confidence == 0.5
    end

    test "handles custom label names" do
      text = "I love this!"
      labels = ["good", "bad"]

      {:ok, result} = Fallback.classify(text, labels)

      assert result.label == "good"
    end

    test "scores sum to approximately 1.0" do
      labels = ["a", "b", "c", "d"]
      {:ok, result} = Fallback.classify("test", labels)

      total = labels |> Enum.map(&Map.get(result.scores, &1)) |> Enum.sum()
      assert_in_delta total, 1.0, 0.01
    end

    test "includes metadata" do
      {:ok, result} = Fallback.classify("test", ["a", "b"])

      assert result.metadata.adapter == :fallback
      assert result.metadata.heuristic == true
    end
  end
end
