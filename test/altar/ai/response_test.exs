defmodule Altar.AI.ResponseTest do
  use ExUnit.Case, async: true

  alias Altar.AI.Response

  describe "normalize_tokens/1" do
    test "normalizes standard format with prompt/completion keys" do
      tokens = %{prompt: 10, completion: 20}
      result = Response.normalize_tokens(tokens)

      assert result == %{prompt: 10, completion: 20, total: 30}
    end

    test "normalizes OpenAI format with _tokens suffix" do
      tokens = %{prompt_tokens: 5, completion_tokens: 15}
      result = Response.normalize_tokens(tokens)

      assert result == %{prompt: 5, completion: 15, total: 20}
    end

    test "normalizes Anthropic format with input/output" do
      tokens = %{input: 8, output: 12}
      result = Response.normalize_tokens(tokens)

      assert result == %{prompt: 8, completion: 12, total: 20}
    end

    test "handles missing tokens" do
      result = Response.normalize_tokens(%{})

      assert result == %{prompt: 0, completion: 0, total: 0}
    end

    test "handles non-map input" do
      result = Response.normalize_tokens(nil)

      assert result == %{prompt: 0, completion: 0, total: 0}
    end
  end

  describe "normalize_finish_reason/1" do
    test "normalizes stop reasons" do
      assert Response.normalize_finish_reason("STOP") == :stop
      assert Response.normalize_finish_reason(:stop) == :stop
      assert Response.normalize_finish_reason(:end) == :stop
      assert Response.normalize_finish_reason(:complete) == :stop
    end

    test "normalizes length reasons" do
      assert Response.normalize_finish_reason("MAX_TOKENS") == :length
      assert Response.normalize_finish_reason(:max_tokens) == :length
      assert Response.normalize_finish_reason(:length) == :length
    end

    test "normalizes error reason" do
      assert Response.normalize_finish_reason(:error) == :error
      assert Response.normalize_finish_reason("ERROR") == :error
    end

    test "handles nil" do
      assert Response.normalize_finish_reason(nil) == :stop
    end

    test "passes through unknown atoms" do
      assert Response.normalize_finish_reason(:custom_reason) == :custom_reason
    end
  end

  describe "extract_content/1" do
    test "extracts from text field" do
      assert Response.extract_content(%{text: "Hello"}) == "Hello"
    end

    test "extracts from content string field" do
      assert Response.extract_content(%{content: "World"}) == "World"
    end

    test "extracts from content array with text" do
      assert Response.extract_content(%{content: [%{text: "Hi"}]}) == "Hi"
    end

    test "extracts from multiple content blocks" do
      content = [%{text: "Hello"}, %{text: " "}, %{text: "World"}]
      assert Response.extract_content(%{content: content}) == "Hello World"
    end

    test "extracts from nested message structure" do
      assert Response.extract_content(%{message: %{content: "Nested"}}) == "Nested"
    end

    test "returns empty string for unknown format" do
      assert Response.extract_content(%{unknown: "field"}) == ""
    end
  end

  describe "extract_metadata/1" do
    test "filters out standard fields" do
      response = %{
        content: "text",
        model: "gpt-4",
        tokens: %{},
        custom_field: "value",
        provider_specific: true
      }

      metadata = Response.extract_metadata(response)

      assert metadata == %{custom_field: "value", provider_specific: true}
      refute Map.has_key?(metadata, :content)
      refute Map.has_key?(metadata, :model)
      refute Map.has_key?(metadata, :tokens)
    end

    test "handles empty response" do
      metadata = Response.extract_metadata(%{})

      assert metadata == %{}
    end
  end
end
