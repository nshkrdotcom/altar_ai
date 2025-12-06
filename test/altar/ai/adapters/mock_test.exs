defmodule Altar.AI.Adapters.MockTest do
  use ExUnit.Case, async: true

  alias Altar.AI
  alias Altar.AI.Adapters.Mock
  alias Altar.AI.{Response, Classification, CodeResult}

  setup do
    {:ok, adapter: Mock.new()}
  end

  describe "generate/3" do
    test "returns default mock response", %{adapter: adapter} do
      {:ok, response} = AI.generate(adapter, "test prompt")

      assert %Response{} = response
      assert response.content =~ "Mock response for: test prompt"
      assert response.provider == :mock
    end

    test "uses configured response" do
      adapter =
        Mock.new()
        |> Mock.with_response(:generate, {:ok, %Response{content: "custom", provider: :mock}})

      {:ok, response} = AI.generate(adapter, "test")
      assert response.content == "custom"
    end

    test "uses function response" do
      adapter =
        Mock.new()
        |> Mock.with_response(:generate, fn prompt ->
          {:ok, %Response{content: "Echo: #{prompt}", provider: :mock, model: "test"}}
        end)

      {:ok, response} = AI.generate(adapter, "hello")
      assert response.content == "Echo: hello"
    end
  end

  describe "embed/3" do
    test "returns mock embedding vector", %{adapter: adapter} do
      {:ok, vector} = AI.embed(adapter, "test text")

      assert is_list(vector)
      assert length(vector) == 256
      assert Enum.all?(vector, &is_float/1)
    end
  end

  describe "batch_embed/3" do
    test "returns mock embedding vectors", %{adapter: adapter} do
      {:ok, vectors} = AI.batch_embed(adapter, ["text1", "text2", "text3"])

      assert is_list(vectors)
      assert length(vectors) == 3
      assert Enum.all?(vectors, fn v -> is_list(v) and length(v) == 256 end)
    end
  end

  describe "classify/4" do
    test "returns mock classification", %{adapter: adapter} do
      {:ok, classification} = AI.classify(adapter, "test", ["positive", "negative"])

      assert %Classification{} = classification
      assert classification.label == "positive"
      assert classification.confidence == 0.95
    end
  end

  describe "generate_code/3" do
    test "returns mock code result", %{adapter: adapter} do
      {:ok, code_result} = AI.generate_code(adapter, "test prompt")

      assert %CodeResult{} = code_result
      assert code_result.code =~ "Mock code for: test prompt"
      assert code_result.language == "elixir"
    end
  end

  describe "explain_code/3" do
    test "returns mock explanation", %{adapter: adapter} do
      {:ok, explanation} = AI.explain_code(adapter, "def test, do: :ok")

      assert is_binary(explanation)
      assert explanation =~ "Mock explanation"
    end
  end
end
