defmodule Altar.AI.ClientTest do
  use ExUnit.Case, async: true

  alias Altar.AI.Adapters.Mock
  alias Altar.AI.{Client, Config, Response}

  describe "new/1" do
    test "creates client with default config" do
      client = Client.new()

      assert %Client{} = client
      assert client.config.default_profile == :default
    end

    test "creates client with custom config" do
      config =
        Config.new(default_profile: :gemini)
        |> Config.add_profile(:gemini, adapter: Mock, model: "gemini-pro")

      client = Client.new(config: config)

      assert client.config.default_profile == :gemini
    end

    test "creates client with inline profile options" do
      client =
        Client.new()
        |> Client.with_profile(:test, adapter: Mock, model: "test-model")

      assert Config.get_profile(client.config, :test) == [adapter: Mock, model: "test-model"]
    end
  end

  describe "with_profile/3" do
    test "adds profile to client config" do
      client =
        Client.new()
        |> Client.with_profile(:gemini, adapter: Mock, model: "gemini-pro")

      assert Config.get_profile(client.config, :gemini) == [adapter: Mock, model: "gemini-pro"]
    end

    test "chains multiple profiles" do
      client =
        Client.new()
        |> Client.with_profile(:gemini, adapter: Mock, model: "gemini-pro")
        |> Client.with_profile(:claude, adapter: Mock, model: "claude-3")

      assert Config.get_profile(client.config, :gemini) != nil
      assert Config.get_profile(client.config, :claude) != nil
    end
  end

  describe "with_default_profile/2" do
    test "sets default profile" do
      client =
        Client.new()
        |> Client.with_profile(:gemini, adapter: Mock)
        |> Client.with_default_profile(:gemini)

      assert client.config.default_profile == :gemini
    end
  end

  describe "generate/3" do
    setup do
      mock =
        Mock.new()
        |> Mock.with_response(:generate, fn _prompt, _opts ->
          {:ok, %Response{content: "Generated text", provider: :mock, model: "mock"}}
        end)

      client =
        Client.new()
        |> Client.with_profile(:test, adapter: mock)
        |> Client.with_default_profile(:test)

      {:ok, client: client}
    end

    test "generates text using default profile", %{client: client} do
      {:ok, response} = Client.generate(client, "Hello")

      assert response.content == "Generated text"
      assert response.provider == :mock
    end

    test "generates text using specified profile" do
      mock =
        Mock.new()
        |> Mock.with_response(:generate, {:ok, %Response{content: "Specific", provider: :mock}})

      client =
        Client.new()
        |> Client.with_profile(:specific, adapter: mock)

      {:ok, response} = Client.generate(client, "Hello", profile: :specific)

      assert response.content == "Specific"
    end

    test "passes options through to adapter" do
      captured_opts = :ets.new(:captured_opts, [:set, :public])

      mock =
        Mock.new()
        |> Mock.with_response(:generate, fn _prompt, opts ->
          :ets.insert(captured_opts, {:opts, opts})
          {:ok, %Response{content: "OK", provider: :mock}}
        end)

      client =
        Client.new()
        |> Client.with_profile(:test, adapter: mock, model: "base-model")
        |> Client.with_default_profile(:test)

      Client.generate(client, "Hello", temperature: 0.9, max_tokens: 100)

      [{:opts, opts}] = :ets.lookup(captured_opts, :opts)
      assert opts[:temperature] == 0.9
      assert opts[:max_tokens] == 100
      assert opts[:model] == "base-model"
    end

    test "returns error from adapter" do
      mock =
        Mock.new()
        |> Mock.with_response(:generate, {:error, %Altar.AI.Error{type: :rate_limit}})

      client =
        Client.new()
        |> Client.with_profile(:test, adapter: mock)
        |> Client.with_default_profile(:test)

      {:error, error} = Client.generate(client, "Hello")

      assert error.type == :rate_limit
    end
  end

  describe "embed/3" do
    test "generates embeddings" do
      mock =
        Mock.new()
        |> Mock.with_response(:embed, {:ok, [0.1, 0.2, 0.3]})

      client =
        Client.new()
        |> Client.with_profile(:test, adapter: mock)
        |> Client.with_default_profile(:test)

      {:ok, embedding} = Client.embed(client, "Hello world")

      assert is_list(embedding)
      assert length(embedding) == 3
    end
  end

  describe "batch_embed/3" do
    test "generates batch embeddings" do
      mock =
        Mock.new()
        |> Mock.with_response(:batch_embed, {:ok, [[0.1, 0.2], [0.3, 0.4]]})

      client =
        Client.new()
        |> Client.with_profile(:test, adapter: mock)
        |> Client.with_default_profile(:test)

      {:ok, embeddings} = Client.batch_embed(client, ["Hello", "World"])

      assert length(embeddings) == 2
    end
  end

  describe "classify/4" do
    test "classifies text" do
      mock =
        Mock.new()
        |> Mock.with_response(:classify, fn _text, _labels, _opts ->
          {:ok, %Altar.AI.Classification{label: "positive", confidence: 0.95}}
        end)

      client =
        Client.new()
        |> Client.with_profile(:test, adapter: mock)
        |> Client.with_default_profile(:test)

      {:ok, result} = Client.classify(client, "Great product!", ["positive", "negative"])

      assert result.label == "positive"
      assert result.confidence == 0.95
    end
  end

  describe "chat_completion/3 (ReqLLM compatibility)" do
    test "handles OpenAI-style messages format" do
      mock =
        Mock.new()
        |> Mock.with_response(:generate, fn prompt, _opts ->
          {:ok, %Response{content: "Response to: #{prompt}", provider: :mock}}
        end)

      client =
        Client.new()
        |> Client.with_profile(:test, adapter: mock)
        |> Client.with_default_profile(:test)

      params = %{
        prompt: "What is 2+2?",
        messages: [%{role: "system", content: "You are helpful."}]
      }

      {:ok, response} = Client.chat_completion(client, params)

      assert response.content =~ "What is 2+2?"
    end

    test "includes metadata with token counts when available" do
      mock =
        Mock.new()
        |> Mock.with_response(:generate, fn _prompt, _opts ->
          {:ok,
           %Response{
             content: "Answer",
             provider: :mock,
             tokens: %{prompt: 10, completion: 5, total: 15}
           }}
        end)

      client =
        Client.new()
        |> Client.with_profile(:test, adapter: mock)
        |> Client.with_default_profile(:test)

      {:ok, response} = Client.chat_completion(client, %{prompt: "Hello"})

      assert response.metadata[:total_tokens] == 15
    end

    test "supports profile option" do
      mock =
        Mock.new()
        |> Mock.with_response(:generate, {:ok, %Response{content: "OK", provider: :mock}})

      client =
        Client.new()
        |> Client.with_profile(:custom, adapter: mock)

      {:ok, _response} = Client.chat_completion(client, %{prompt: "Hi"}, profile: :custom)
    end
  end

  describe "get_adapter/2" do
    test "returns adapter for profile" do
      mock = Mock.new()

      client =
        Client.new()
        |> Client.with_profile(:test, adapter: mock)

      adapter = Client.get_adapter(client, :test)

      assert adapter == mock
    end

    test "returns nil for unknown profile" do
      client = Client.new()

      assert Client.get_adapter(client, :unknown) == nil
    end
  end

  describe "capabilities/2" do
    test "returns capabilities for profile adapter" do
      mock = Mock.new()

      client =
        Client.new()
        |> Client.with_profile(:test, adapter: mock)

      caps = Client.capabilities(client, :test)

      assert caps.generate == true
      assert caps.embed == true
    end
  end
end
