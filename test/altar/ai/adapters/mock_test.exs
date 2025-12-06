defmodule Altar.AI.Adapters.MockTest do
  use ExUnit.Case, async: false

  alias Altar.AI.Adapters.Mock

  setup do
    Mock.reset()
    :ok
  end

  describe "generate/2" do
    test "returns default response" do
      {:ok, response} = Mock.generate("Hello")

      assert response.content =~ "mocked response"
      assert response.model == "mock-model"
      assert response.tokens.total > 0
      assert response.finish_reason == :stop
    end

    test "returns configured response" do
      custom_response =
        {:ok,
         %{
           content: "Custom",
           model: "test",
           tokens: %{prompt: 1, completion: 1, total: 2},
           finish_reason: :stop,
           metadata: %{}
         }}

      Mock.set_response(:generate, custom_response)

      assert Mock.generate("Test") == custom_response
    end

    test "tracks calls" do
      Mock.generate("Hello", temperature: 0.5)

      calls = Mock.get_calls(:generate)
      assert length(calls) == 1
      assert [["Hello", [temperature: 0.5]]] = calls
    end
  end

  describe "stream/2" do
    test "returns stream" do
      {:ok, stream} = Mock.stream("Tell me a story")

      chunks = Enum.to_list(stream)
      assert length(chunks) > 0
      assert %{content: _, delta: _, finish_reason: _} = List.first(chunks)
    end

    test "tracks calls" do
      Mock.stream("Story")

      calls = Mock.get_calls(:stream)
      assert length(calls) == 1
    end
  end

  describe "embed/2" do
    test "returns embedding vector" do
      {:ok, response} = Mock.embed("test text")

      assert is_list(response.vector)
      assert length(response.vector) == 768
      assert response.dimensions == 768
      assert response.model == "mock-embed"
    end

    test "tracks calls" do
      Mock.embed("semantic search")

      calls = Mock.get_calls(:embed)
      assert [["semantic search", []]] = calls
    end
  end

  describe "batch_embed/2" do
    test "returns multiple embeddings" do
      texts = ["text1", "text2", "text3"]
      {:ok, response} = Mock.batch_embed(texts)

      assert length(response.vectors) == 3
      assert response.dimensions == 768

      Enum.each(response.vectors, fn vector ->
        assert is_list(vector)
        assert length(vector) == 768
      end)
    end

    test "tracks calls" do
      Mock.batch_embed(["a", "b"])

      calls = Mock.get_calls(:batch_embed)
      assert [[["a", "b"], []]] = calls
    end
  end

  describe "classify/3" do
    test "returns classification result" do
      {:ok, result} = Mock.classify("I love this!", ["positive", "negative", "neutral"])

      assert result.label == "positive"
      assert result.confidence == 0.95
      assert Map.has_key?(result.scores, "positive")
      assert Map.has_key?(result.scores, "negative")
      assert Map.has_key?(result.scores, "neutral")
    end

    test "generates realistic scores for provided labels" do
      labels = ["happy", "sad", "angry", "neutral"]
      {:ok, result} = Mock.classify("text", labels)

      # All labels should have scores
      Enum.each(labels, fn label ->
        assert Map.has_key?(result.scores, label)
      end)

      # Scores should sum to approximately 1.0
      total = labels |> Enum.map(&Map.get(result.scores, &1)) |> Enum.sum()
      assert_in_delta total, 1.0, 0.01
    end

    test "tracks calls" do
      Mock.classify("text", ["a", "b"])

      calls = Mock.get_calls(:classify)
      assert [["text", ["a", "b"], []]] = calls
    end
  end

  describe "generate_code/2" do
    test "returns code generation result" do
      {:ok, response} = Mock.generate_code("fibonacci function")

      assert response.code =~ "def"
      assert response.language == "elixir"
      assert response.model == "mock-code"
    end

    test "tracks calls" do
      Mock.generate_code("create function")

      calls = Mock.get_calls(:generate_code)
      assert length(calls) == 1
    end
  end

  describe "explain_code/2" do
    test "returns code explanation" do
      {:ok, response} = Mock.explain_code("def hello, do: :world")

      assert is_binary(response.explanation)
      assert response.language == "elixir"
      assert response.complexity == :simple
    end

    test "tracks calls" do
      Mock.explain_code("code here")

      calls = Mock.get_calls(:explain_code)
      assert length(calls) == 1
    end
  end

  describe "call tracking" do
    test "get_calls/0 returns all calls" do
      Mock.generate("test1")
      Mock.embed("test2")
      Mock.classify("test3", ["a", "b"])

      calls = Mock.get_calls()
      assert length(calls) == 3
    end

    test "get_calls/1 filters by function" do
      Mock.generate("test1")
      Mock.generate("test2")
      Mock.embed("test3")

      generate_calls = Mock.get_calls(:generate)
      assert length(generate_calls) == 2

      embed_calls = Mock.get_calls(:embed)
      assert length(embed_calls) == 1
    end

    test "clear_calls/0 removes all calls" do
      Mock.generate("test")
      Mock.clear_calls()

      assert Mock.get_calls() == []
    end

    test "reset/0 clears calls and responses" do
      Mock.set_response(:generate, {:ok, %{content: "Custom"}})
      Mock.generate("test")

      Mock.reset()

      assert Mock.get_calls() == []
      # Should return default response after reset
      {:ok, response} = Mock.generate("test")
      assert response.content =~ "mocked response"
    end
  end
end
