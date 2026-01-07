defmodule Altar.AI.Adapters.FallbackTest do
  use ExUnit.Case, async: true

  alias Altar.AI
  alias Altar.AI.Adapters.Fallback
  alias Altar.AI.{Classification, Response}

  setup do
    {:ok, adapter: Fallback.new()}
  end

  describe "generate/3" do
    test "returns fallback response", %{adapter: adapter} do
      {:ok, response} = AI.generate(adapter, "test prompt")

      assert %Response{} = response
      assert response.content =~ "[Fallback]"
      assert response.provider == :fallback
      assert response.finish_reason == :fallback
    end
  end

  describe "classify/4" do
    test "performs keyword-based classification", %{adapter: adapter} do
      {:ok, classification} =
        AI.classify(adapter, "I am positive about this", ["positive", "negative"])

      assert %Classification{} = classification
      assert classification.label == "positive"
      assert classification.confidence == 0.8
    end

    test "returns first label when no match", %{adapter: adapter} do
      {:ok, classification} = AI.classify(adapter, "neutral text", ["happy", "sad"])

      assert %Classification{} = classification
      assert classification.label in ["happy", "sad"]
      assert classification.confidence == 0.2
    end
  end

  describe "available?/0" do
    test "always returns true" do
      assert Fallback.available?() == true
    end
  end
end
