defmodule Altar.AI.Adapters.CompositeTest do
  use ExUnit.Case, async: true

  alias Altar.AI
  alias Altar.AI.Adapters.{Composite, Fallback, Mock}
  alias Altar.AI.{Error, Response}

  describe "new/2" do
    test "creates composite with provided adapters" do
      mock = Mock.new()
      fallback = Fallback.new()

      composite = Composite.new([mock, fallback])

      assert %Composite{} = composite
      assert composite.providers == [mock, fallback]
      assert composite.strategy == :fallback
    end
  end

  describe "default/0" do
    test "creates default composite" do
      composite = Composite.default()

      assert %Composite{} = composite
      assert is_list(composite.providers)
      assert Enum.any?(composite.providers, &match?(%Fallback{}, &1))
    end
  end

  describe "generate/3 with fallback strategy" do
    test "uses first successful adapter" do
      mock1 =
        Mock.new()
        |> Mock.with_response(
          :generate,
          {:error, Error.new(:rate_limit, "error", retryable?: true)}
        )

      mock2 =
        Mock.new()
        |> Mock.with_response(
          :generate,
          {:ok, %Response{content: "success", provider: :mock2, model: "test"}}
        )

      composite = Composite.new([mock1, mock2])

      {:ok, response} = AI.generate(composite, "test")
      assert response.content == "success"
    end

    test "tries all adapters until one succeeds" do
      fallback = Fallback.new()
      composite = Composite.new([fallback])

      {:ok, response} = AI.generate(composite, "test")
      assert response.provider == :fallback
    end
  end

  describe "capabilities" do
    test "composite supports all capabilities its providers support" do
      mock = Mock.new()
      fallback = Fallback.new()
      composite = Composite.new([mock, fallback])

      # Composite should support capabilities from any of its providers
      assert AI.supports?(composite, :generate) == true
      assert AI.supports?(composite, :embed) == true
      assert AI.supports?(composite, :classify) == true
    end
  end
end
