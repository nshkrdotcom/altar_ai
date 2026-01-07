defmodule Altar.AI.Integrations.SynapseTest do
  use ExUnit.Case, async: true

  alias Altar.AI.Adapters.Mock
  alias Altar.AI.Config
  alias Altar.AI.Integrations.Synapse, as: SynapseIntegration
  alias Altar.AI.Response

  describe "chat_completion/2 (ReqLLM-compatible interface)" do
    test "generates text from prompt" do
      mock =
        Mock.new()
        |> Mock.with_response(:generate, {:ok, %Response{content: "42", provider: :mock}})

      config =
        Config.new()
        |> Config.add_profile(:test, adapter: mock, model: "test-model")

      params = %{prompt: "What is 2+2?"}

      {:ok, response} = SynapseIntegration.chat_completion(params, config: config, profile: :test)

      assert response.content == "42"
    end

    test "includes metadata with token counts" do
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

      config =
        Config.new()
        |> Config.add_profile(:test, adapter: mock)

      {:ok, response} =
        SynapseIntegration.chat_completion(%{prompt: "Hi"}, config: config, profile: :test)

      assert response.metadata.total_tokens == 15
    end

    test "handles messages array with system prompt" do
      captured = :ets.new(:captured, [:set, :public])

      mock =
        Mock.new()
        |> Mock.with_response(:generate, fn prompt, _opts ->
          :ets.insert(captured, {:prompt, prompt})
          {:ok, %Response{content: "OK", provider: :mock}}
        end)

      config =
        Config.new()
        |> Config.add_profile(:test, adapter: mock)

      params = %{
        prompt: "What is AI?",
        messages: [
          %{role: "system", content: "You are an expert."}
        ]
      }

      {:ok, _} = SynapseIntegration.chat_completion(params, config: config, profile: :test)

      [{:prompt, prompt}] = :ets.lookup(captured, :prompt)
      assert prompt =~ "You are an expert"
      assert prompt =~ "What is AI?"
    end

    test "passes temperature and max_tokens" do
      captured = :ets.new(:captured, [:set, :public])

      mock =
        Mock.new()
        |> Mock.with_response(:generate, fn _prompt, opts ->
          :ets.insert(captured, {:opts, opts})
          {:ok, %Response{content: "OK", provider: :mock}}
        end)

      config =
        Config.new()
        |> Config.add_profile(:test, adapter: mock)

      params = %{
        prompt: "Hello",
        temperature: 0.7,
        max_tokens: 100
      }

      {:ok, _} = SynapseIntegration.chat_completion(params, config: config, profile: :test)

      [{:opts, opts}] = :ets.lookup(captured, :opts)
      assert opts[:temperature] == 0.7
      assert opts[:max_tokens] == 100
    end

    test "returns error on failure" do
      mock =
        Mock.new()
        |> Mock.with_response(
          :generate,
          {:error, %Altar.AI.Error{type: :rate_limit, message: "Rate limited"}}
        )

      config =
        Config.new()
        |> Config.add_profile(:test, adapter: mock)

      {:error, error} =
        SynapseIntegration.chat_completion(%{prompt: "Hi"}, config: config, profile: :test)

      assert error.type == :rate_limit
    end
  end

  describe "from_synapse_config/1" do
    test "converts Synapse profile config to Altar.AI config" do
      synapse_config = %{
        default_profile: :openai,
        profiles: %{
          openai: [
            model: "gpt-4",
            temperature: 0.7,
            max_tokens: 1000
          ],
          gemini: [
            model: "gemini-pro",
            temperature: 0.5
          ]
        },
        system_prompt: "You are helpful."
      }

      config = SynapseIntegration.from_synapse_config(synapse_config)

      assert config.default_profile == :openai
      assert Config.get_profile(config, :openai)[:model] == "gpt-4"
      assert Config.get_profile(config, :gemini)[:model] == "gemini-pro"
      assert config.global_opts[:system_prompt] == "You are helpful."
    end

    test "uses default profile when not specified" do
      synapse_config = %{profiles: %{}}

      config = SynapseIntegration.from_synapse_config(synapse_config)

      assert config.default_profile == :default
    end
  end

  describe "from_application_env/0" do
    setup do
      # Save current config
      original = Application.get_all_env(:synapse)

      on_exit(fn ->
        # Restore original config
        Enum.each(Application.get_all_env(:synapse), fn {key, _} ->
          Application.delete_env(:synapse, key)
        end)

        Enum.each(original, fn {key, value} ->
          Application.put_env(:synapse, key, value)
        end)
      end)

      :ok
    end

    test "loads config from :synapse application env" do
      Application.put_env(:synapse, Synapse.ReqLLM,
        default_profile: :openai,
        profiles: %{
          openai: [model: "gpt-4"]
        }
      )

      config = SynapseIntegration.from_application_env()

      assert config.default_profile == :openai
      assert Config.get_profile(config, :openai)[:model] == "gpt-4"
    end
  end

  describe "generate/3" do
    test "generates text using specified profile" do
      mock =
        Mock.new()
        |> Mock.with_response(:generate, {:ok, %Response{content: "Generated", provider: :mock}})

      config =
        Config.new()
        |> Config.add_profile(:test, adapter: mock)

      {:ok, response} = SynapseIntegration.generate("Hello", config: config, profile: :test)

      assert response.content == "Generated"
    end
  end

  describe "stream/3" do
    test "streams text using specified profile" do
      mock =
        Mock.new()
        |> Mock.with_response(:stream, {:ok, Stream.map(["chunk1", "chunk2"], & &1)})

      config =
        Config.new()
        |> Config.add_profile(:test, adapter: mock)

      {:ok, stream} = SynapseIntegration.stream("Tell a story", config: config, profile: :test)

      chunks = Enum.to_list(stream)
      assert length(chunks) == 2
    end
  end
end
