defmodule Altar.AITest do
  use ExUnit.Case, async: false

  alias Altar.AI
  alias Altar.AI.Adapters.Mock

  setup do
    # Configure to use Mock adapter
    Application.put_env(:altar_ai, :default_adapter, Mock)
    Mock.reset()

    on_exit(fn ->
      Application.delete_env(:altar_ai, :default_adapter)
    end)

    :ok
  end

  describe "generate/2" do
    test "generates text using default adapter" do
      {:ok, response} = AI.generate("Hello")

      assert is_binary(response.content)
      assert is_binary(response.model)
      assert is_map(response.tokens)
      assert response.finish_reason in [:stop, :length, :error]
    end

    test "passes options to adapter" do
      {:ok, _response} = AI.generate("Test", temperature: 0.7, max_tokens: 100)

      calls = Mock.get_calls(:generate)
      assert [["Test", opts]] = calls
      assert Keyword.get(opts, :temperature) == 0.7
      assert Keyword.get(opts, :max_tokens) == 100
    end

    test "uses custom adapter when specified" do
      custom_response =
        {:ok,
         %{
           content: "Custom adapter response",
           model: "custom",
           tokens: %{prompt: 1, completion: 1, total: 2},
           finish_reason: :stop,
           metadata: %{}
         }}

      Mock.set_response(:generate, custom_response)

      {:ok, response} = AI.generate("Test", adapter: Mock)

      assert response.content == "Custom adapter response"
    end
  end

  describe "stream/2" do
    test "streams text generation" do
      {:ok, stream} = AI.stream("Tell me a story")

      chunks = Enum.to_list(stream)
      assert length(chunks) > 0

      chunk = List.first(chunks)
      assert is_binary(chunk.content)
      assert is_boolean(chunk.delta)
    end
  end

  describe "embed/2" do
    test "generates embeddings" do
      {:ok, response} = AI.embed("semantic search")

      assert is_list(response.vector)
      assert response.dimensions > 0
      assert is_binary(response.model)
    end

    test "passes options to adapter" do
      {:ok, _response} = AI.embed("test", model: "custom-embed")

      calls = Mock.get_calls(:embed)
      assert [["test", opts]] = calls
      assert Keyword.get(opts, :model) == "custom-embed"
    end
  end

  describe "batch_embed/2" do
    test "generates batch embeddings" do
      texts = ["query 1", "query 2", "query 3"]
      {:ok, response} = AI.batch_embed(texts)

      assert is_list(response.vectors)
      assert length(response.vectors) == 3
      assert response.dimensions > 0
    end
  end

  describe "classify/3" do
    test "classifies text" do
      {:ok, result} = AI.classify("I love this!", ["positive", "negative", "neutral"])

      assert result.label in ["positive", "negative", "neutral"]
      assert is_float(result.confidence)
      assert is_map(result.scores)
    end

    test "passes options to adapter" do
      {:ok, _result} = AI.classify("test", ["a", "b"], threshold: 0.8)

      calls = Mock.get_calls(:classify)
      assert [["test", ["a", "b"], opts]] = calls
      assert Keyword.get(opts, :threshold) == 0.8
    end
  end

  describe "generate_code/2" do
    test "generates code" do
      {:ok, response} = AI.generate_code("fibonacci function")

      assert is_binary(response.code)
      assert is_binary(response.model)
    end

    test "passes language option" do
      {:ok, _response} = AI.generate_code("create function", language: "python")

      calls = Mock.get_calls(:generate_code)
      assert [["create function", opts]] = calls
      assert Keyword.get(opts, :language) == "python"
    end
  end

  describe "explain_code/2" do
    test "explains code" do
      {:ok, response} = AI.explain_code("def hello, do: :world")

      assert is_binary(response.explanation)
      assert is_binary(response.model)
    end

    test "passes options to adapter" do
      {:ok, _response} = AI.explain_code("code", language: "elixir", detail_level: :detailed)

      calls = Mock.get_calls(:explain_code)
      assert [["code", opts]] = calls
      assert Keyword.get(opts, :language) == "elixir"
      assert Keyword.get(opts, :detail_level) == :detailed
    end
  end
end
