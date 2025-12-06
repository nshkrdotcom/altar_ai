defmodule Altar.AITest do
  use ExUnit.Case, async: true

  alias Altar.AI

  describe "default_adapter/0" do
    test "returns a composite adapter" do
      adapter = AI.default_adapter()
      assert %Altar.AI.Adapters.Composite{} = adapter
    end
  end

  describe "available_adapters/0" do
    test "returns list of available adapters" do
      adapters = AI.available_adapters()
      assert is_list(adapters)
      assert Altar.AI.Adapters.Fallback in adapters
      assert Altar.AI.Adapters.Mock in adapters
    end
  end

  describe "capabilities/1" do
    test "returns capabilities map for mock adapter" do
      mock = Altar.AI.Adapters.Mock.new()
      caps = AI.capabilities(mock)

      assert is_map(caps)
      assert caps.generate == true
      assert caps.embed == true
      assert caps.classify == true
    end

    test "returns capabilities map for fallback adapter" do
      fallback = Altar.AI.Adapters.Fallback.new()
      caps = AI.capabilities(fallback)

      assert is_map(caps)
      assert caps.generate == true
      assert caps.classify == true
      assert caps.embed == false
    end
  end

  describe "supports?/2" do
    test "checks if adapter supports capability" do
      mock = Altar.AI.Adapters.Mock.new()
      assert AI.supports?(mock, :generate) == true
      assert AI.supports?(mock, :embed) == true
    end
  end
end
