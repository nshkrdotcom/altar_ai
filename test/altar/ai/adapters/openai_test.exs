defmodule Altar.AI.Adapters.OpenAITest do
  use ExUnit.Case, async: true

  alias Altar.AI.Adapters.OpenAI
  alias Altar.AI.{Embedder, Generator, Response}

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, base_url: "http://localhost:#{bypass.port}/v1"}
  end

  describe "new/1" do
    test "creates adapter with api_key" do
      adapter = OpenAI.new(api_key: "test-key")
      assert %OpenAI{} = adapter
    end
  end

  describe "Generator protocol" do
    test "generates text", %{bypass: bypass, base_url: base_url} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "gpt-4o"
        assert decoded["messages"] == [%{"role" => "user", "content" => "Hello"}]

        response = %{
          "id" => "chatcmpl_test",
          "object" => "chat.completion",
          "created" => 1_700_000_000,
          "model" => "gpt-4o",
          "choices" => [
            %{
              "index" => 0,
              "message" => %{"role" => "assistant", "content" => "Hi"},
              "finish_reason" => "stop"
            }
          ],
          "usage" => %{"prompt_tokens" => 2, "completion_tokens" => 3, "total_tokens" => 5}
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      adapter = OpenAI.new(api_key: "test-key", base_url: base_url, model: "gpt-4o")

      assert {:ok, %Response{} = response} = Generator.generate(adapter, "Hello", [])
      assert response.content == "Hi"
      assert response.model == "gpt-4o"
      assert response.tokens.prompt == 2
      assert response.tokens.completion == 3
      assert response.tokens.total == 5
    end

    test "streams text chunks", %{bypass: bypass, base_url: base_url} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn =
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_chunked(200)

        {:ok, conn} =
          Plug.Conn.chunk(conn, "data: {\"choices\":[{\"delta\":{\"content\":\"Hello \"}}]}\n\n")

        {:ok, conn} =
          Plug.Conn.chunk(conn, "data: {\"choices\":[{\"delta\":{\"content\":\"world\"}}]}\n\n")

        {:ok, conn} =
          Plug.Conn.chunk(conn, "data: {\"choices\":[{\"finish_reason\":\"stop\"}]}\n\n")

        {:ok, conn} = Plug.Conn.chunk(conn, "data: [DONE]\n\n")
        conn
      end)

      adapter = OpenAI.new(api_key: "test-key", base_url: base_url, model: "gpt-4o")

      assert {:ok, stream} = Generator.stream(adapter, "Hello", [])

      chunks = Enum.to_list(stream)

      assert Enum.any?(chunks, &(&1.delta == "Hello "))
      assert Enum.any?(chunks, &(&1.delta == "world"))
      assert Enum.any?(chunks, &(&1.finish_reason == :stop))
    end
  end

  describe "Embedder protocol" do
    test "embeds text", %{bypass: bypass, base_url: base_url} do
      embedding = [0.1, 0.2, 0.3]

      Bypass.expect(bypass, "POST", "/v1/embeddings", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["model"] == "text-embedding-3-small"
        assert decoded["input"] == ["Hello"]

        response = %{
          "data" => [
            %{
              "object" => "embedding",
              "index" => 0,
              "embedding" => embedding
            }
          ],
          "model" => "text-embedding-3-small",
          "usage" => %{"prompt_tokens" => 3, "total_tokens" => 3}
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      adapter = OpenAI.new(api_key: "test-key", base_url: base_url)

      assert {:ok, vector} = Embedder.embed(adapter, "Hello", [])
      assert vector == embedding
    end

    test "batch embeds texts", %{bypass: bypass, base_url: base_url} do
      embedding_one = [0.1, 0.2]
      embedding_two = [0.3, 0.4]

      Bypass.expect(bypass, "POST", "/v1/embeddings", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["input"] == ["first", "second"]

        response = %{
          "data" => [
            %{"index" => 1, "embedding" => embedding_two},
            %{"index" => 0, "embedding" => embedding_one}
          ],
          "model" => "text-embedding-3-small",
          "usage" => %{"prompt_tokens" => 4, "total_tokens" => 4}
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(response))
      end)

      adapter = OpenAI.new(api_key: "test-key", base_url: base_url)

      assert {:ok, vectors} = Embedder.batch_embed(adapter, ["first", "second"], [])
      assert vectors == [embedding_one, embedding_two]
    end
  end
end
