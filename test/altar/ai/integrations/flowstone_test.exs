defmodule Altar.AI.Integrations.FlowStoneTest do
  use ExUnit.Case, async: true

  alias Altar.AI.Adapters.Mock
  alias Altar.AI.Classification
  alias Altar.AI.Integrations.FlowStone, as: FlowStoneIntegration
  alias Altar.AI.Response

  describe "init/1" do
    test "creates resource with default adapter" do
      {:ok, resource} = FlowStoneIntegration.init([])

      assert resource.adapter != nil
    end

    test "creates resource with custom adapter" do
      mock = Mock.new()

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      assert resource.adapter == mock
    end
  end

  describe "generate/3" do
    test "generates text" do
      mock =
        Mock.new()
        |> Mock.with_response(:generate, {:ok, %Response{content: "Generated", provider: :mock}})

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      {:ok, response} = FlowStoneIntegration.generate(resource, "Hello")

      assert response.content == "Generated"
    end
  end

  describe "embed/3" do
    test "generates embeddings" do
      mock =
        Mock.new()
        |> Mock.with_response(:embed, {:ok, [0.1, 0.2, 0.3]})

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      {:ok, embedding} = FlowStoneIntegration.embed(resource, "Hello world")

      assert is_list(embedding)
      assert length(embedding) == 3
    end
  end

  describe "batch_embed/3" do
    test "generates batch embeddings" do
      mock =
        Mock.new()
        |> Mock.with_response(:batch_embed, {:ok, [[0.1, 0.2], [0.3, 0.4]]})

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      {:ok, embeddings} = FlowStoneIntegration.batch_embed(resource, ["Hello", "World"])

      assert length(embeddings) == 2
    end
  end

  describe "classify/4" do
    test "classifies text" do
      mock =
        Mock.new()
        |> Mock.with_response(
          :classify,
          {:ok, %Classification{label: "positive", confidence: 0.9}}
        )

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      {:ok, result} = FlowStoneIntegration.classify(resource, "Great!", ["positive", "negative"])

      assert result.label == "positive"
    end
  end

  describe "capabilities/1" do
    test "returns adapter capabilities" do
      mock = Mock.new()

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      caps = FlowStoneIntegration.capabilities(resource)

      assert caps.generate == true
      assert caps.embed == true
    end
  end

  describe "health_check/1" do
    test "returns healthy when adapter has generate capability" do
      mock = Mock.new()

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      assert :healthy == FlowStoneIntegration.health_check(resource)
    end
  end

  describe "classify_each/5 (DSL helper)" do
    test "classifies multiple items" do
      mock =
        Mock.new()
        |> Mock.with_response(:classify, fn text, _labels, _opts ->
          label = if String.contains?(text, "great"), do: "positive", else: "negative"
          {:ok, %Classification{label: label, confidence: 0.9}}
        end)

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      items = [
        %{id: 1, text: "This is great!"},
        %{id: 2, text: "This is bad"}
      ]

      {:ok, results} =
        FlowStoneIntegration.classify_each(resource, items, & &1.text, ["positive", "negative"])

      assert length(results) == 2

      [first, second] = results
      assert first.classification == "positive"
      assert second.classification == "negative"
    end

    test "preserves original item data" do
      mock =
        Mock.new()
        |> Mock.with_response(
          :classify,
          {:ok, %Classification{label: "positive", confidence: 0.9}}
        )

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      items = [%{id: 1, text: "Hello", extra: "data"}]

      {:ok, [result]} =
        FlowStoneIntegration.classify_each(resource, items, & &1.text, ["positive"])

      assert result.id == 1
      assert result.extra == "data"
    end

    test "handles empty list" do
      mock = Mock.new()

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      {:ok, results} = FlowStoneIntegration.classify_each(resource, [], & &1.text, ["positive"])

      assert results == []
    end
  end

  describe "enrich_each/4 (DSL helper)" do
    test "enriches multiple items" do
      mock =
        Mock.new()
        |> Mock.with_response(:generate, fn prompt, _opts ->
          {:ok, %Response{content: "Enriched: #{prompt}", provider: :mock}}
        end)

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      items = [
        %{id: 1, text: "Hello"},
        %{id: 2, text: "World"}
      ]

      {:ok, results} =
        FlowStoneIntegration.enrich_each(resource, items, fn item -> "Summarize: #{item.text}" end)

      assert length(results) == 2

      [first, _second] = results
      assert first.ai_enrichment =~ "Summarize: Hello"
    end

    test "preserves original item data" do
      mock =
        Mock.new()
        |> Mock.with_response(:generate, {:ok, %Response{content: "Enriched", provider: :mock}})

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      items = [%{id: 1, text: "Hello", extra: "data"}]

      {:ok, [result]} = FlowStoneIntegration.enrich_each(resource, items, & &1.text)

      assert result.id == 1
      assert result.extra == "data"
      assert result.ai_enrichment == "Enriched"
    end
  end

  describe "embed_each/4 (DSL helper)" do
    test "embeds multiple items using batch" do
      mock =
        Mock.new()
        |> Mock.with_response(:batch_embed, {:ok, [[0.1, 0.2], [0.3, 0.4]]})

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      items = [
        %{id: 1, text: "Hello"},
        %{id: 2, text: "World"}
      ]

      {:ok, results} = FlowStoneIntegration.embed_each(resource, items, & &1.text)

      assert length(results) == 2

      [first, second] = results
      assert first.embedding == [0.1, 0.2]
      assert second.embedding == [0.3, 0.4]
    end

    test "propagates error from batch embed" do
      mock =
        Mock.new()
        |> Mock.with_response(:batch_embed, {:error, %Altar.AI.Error{type: :rate_limit}})

      {:ok, resource} = FlowStoneIntegration.init(adapter: mock)

      items = [%{id: 1, text: "Hello"}]

      {:error, error} = FlowStoneIntegration.embed_each(resource, items, & &1.text)

      assert error.type == :rate_limit
    end
  end

  describe "available?/0" do
    test "returns true since this is the integration module" do
      assert FlowStoneIntegration.available?() == true
    end
  end
end
