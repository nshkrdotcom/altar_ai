defmodule Altar.AI.ConfigTest do
  use ExUnit.Case, async: true

  alias Altar.AI.Config

  describe "new/1" do
    test "creates config with default values" do
      config = Config.new()

      assert config.default_profile == :default
      assert config.profiles == %{}
      assert config.global_opts == []
    end

    test "creates config with custom default profile" do
      config = Config.new(default_profile: :gemini)

      assert config.default_profile == :gemini
    end

    test "creates config with profiles" do
      profiles = %{
        gemini: [model: "gemini-pro", api_key: "test-key"],
        claude: [model: "claude-3-opus"]
      }

      config = Config.new(profiles: profiles)

      assert config.profiles == profiles
    end

    test "creates config with global options" do
      config = Config.new(global_opts: [timeout: 30_000, max_retries: 3])

      assert config.global_opts == [timeout: 30_000, max_retries: 3]
    end
  end

  describe "add_profile/3" do
    test "adds a new profile" do
      config =
        Config.new()
        |> Config.add_profile(:gemini, model: "gemini-pro", api_key: "test-key")

      assert Config.get_profile(config, :gemini) == [model: "gemini-pro", api_key: "test-key"]
    end

    test "overwrites existing profile" do
      config =
        Config.new()
        |> Config.add_profile(:gemini, model: "gemini-pro")
        |> Config.add_profile(:gemini, model: "gemini-1.5-pro")

      assert Config.get_profile(config, :gemini) == [model: "gemini-1.5-pro"]
    end
  end

  describe "get_profile/2" do
    test "returns profile options when profile exists" do
      config =
        Config.new()
        |> Config.add_profile(:gemini, model: "gemini-pro")

      assert Config.get_profile(config, :gemini) == [model: "gemini-pro"]
    end

    test "returns nil when profile does not exist" do
      config = Config.new()

      assert Config.get_profile(config, :nonexistent) == nil
    end
  end

  describe "resolve_opts/3" do
    test "merges global opts with profile opts" do
      config =
        Config.new(global_opts: [timeout: 30_000, max_retries: 3])
        |> Config.add_profile(:gemini, model: "gemini-pro", timeout: 60_000)

      resolved = Config.resolve_opts(config, :gemini)

      assert resolved[:timeout] == 60_000
      assert resolved[:max_retries] == 3
      assert resolved[:model] == "gemini-pro"
    end

    test "merges call opts on top of profile and global opts" do
      config =
        Config.new(global_opts: [timeout: 30_000])
        |> Config.add_profile(:gemini, model: "gemini-pro", temperature: 0.7)

      resolved = Config.resolve_opts(config, :gemini, temperature: 0.9, custom: true)

      assert resolved[:timeout] == 30_000
      assert resolved[:model] == "gemini-pro"
      assert resolved[:temperature] == 0.9
      assert resolved[:custom] == true
    end

    test "uses default profile when profile is :default" do
      config =
        Config.new(default_profile: :gemini)
        |> Config.add_profile(:gemini, model: "gemini-pro")

      resolved = Config.resolve_opts(config, :default)

      assert resolved[:model] == "gemini-pro"
    end

    test "returns global opts when profile not found" do
      config = Config.new(global_opts: [timeout: 30_000])

      resolved = Config.resolve_opts(config, :nonexistent)

      assert resolved[:timeout] == 30_000
    end
  end

  describe "from_application_env/1" do
    setup do
      # Save current config
      original = Application.get_all_env(:altar_ai)

      on_exit(fn ->
        # Restore original config
        Enum.each(Application.get_all_env(:altar_ai), fn {key, _} ->
          Application.delete_env(:altar_ai, key)
        end)

        Enum.each(original, fn {key, value} ->
          Application.put_env(:altar_ai, key, value)
        end)
      end)

      :ok
    end

    test "loads config from application environment" do
      Application.put_env(:altar_ai, :default_profile, :gemini)

      Application.put_env(:altar_ai, :profiles, %{
        gemini: [model: "gemini-pro", api_key: "test-key"]
      })

      Application.put_env(:altar_ai, :global_opts, timeout: 30_000)

      config = Config.from_application_env()

      assert config.default_profile == :gemini
      assert config.profiles[:gemini] == [model: "gemini-pro", api_key: "test-key"]
      assert config.global_opts == [timeout: 30_000]
    end

    test "uses defaults when environment is not configured" do
      config = Config.from_application_env()

      assert config.default_profile == :default
      assert config.profiles == %{}
      assert config.global_opts == []
    end
  end

  describe "get_adapter/2" do
    test "returns adapter module for profile" do
      config =
        Config.new()
        |> Config.add_profile(:gemini, adapter: Altar.AI.Adapters.Gemini, model: "gemini-pro")

      assert Config.get_adapter(config, :gemini) == Altar.AI.Adapters.Gemini
    end

    test "returns nil when profile has no adapter" do
      config =
        Config.new()
        |> Config.add_profile(:gemini, model: "gemini-pro")

      assert Config.get_adapter(config, :gemini) == nil
    end

    test "returns nil when profile does not exist" do
      config = Config.new()

      assert Config.get_adapter(config, :nonexistent) == nil
    end
  end

  describe "system_prompt/2" do
    test "returns system prompt from profile" do
      config =
        Config.new()
        |> Config.add_profile(:gemini, system_prompt: "You are a helpful assistant.")

      assert Config.system_prompt(config, :gemini) == "You are a helpful assistant."
    end

    test "returns global system prompt when profile has none" do
      config =
        Config.new(global_opts: [system_prompt: "Global system prompt"])
        |> Config.add_profile(:gemini, model: "gemini-pro")

      assert Config.system_prompt(config, :gemini) == "Global system prompt"
    end

    test "returns nil when no system prompt configured" do
      config =
        Config.new()
        |> Config.add_profile(:gemini, model: "gemini-pro")

      assert Config.system_prompt(config, :gemini) == nil
    end

    test "profile system prompt takes precedence over global" do
      config =
        Config.new(global_opts: [system_prompt: "Global"])
        |> Config.add_profile(:gemini, system_prompt: "Profile specific")

      assert Config.system_prompt(config, :gemini) == "Profile specific"
    end
  end

  describe "retry_config/2" do
    test "returns retry config from profile merged with defaults" do
      config =
        Config.new()
        |> Config.add_profile(:gemini, retry: [max_attempts: 5, base_delay_ms: 1000])

      retry = Config.retry_config(config, :gemini)

      # Profile overrides
      assert retry[:max_attempts] == 5
      assert retry[:base_delay_ms] == 1000
      # Defaults preserved
      assert retry[:max_delay_ms] == 10_000
      assert retry[:jitter] == true
    end

    test "returns default retry config when not configured" do
      config =
        Config.new()
        |> Config.add_profile(:gemini, model: "gemini-pro")

      retry = Config.retry_config(config, :gemini)

      assert retry[:max_attempts] == 3
      assert retry[:base_delay_ms] == 500
    end
  end

  describe "validate!/1" do
    test "returns config when valid" do
      config = Config.new(default_profile: :default)

      assert Config.validate!(config) == config
    end

    test "raises when default profile references non-existent profile" do
      config = Config.new(default_profile: :nonexistent)

      assert_raise ArgumentError, ~r/default profile :nonexistent is not defined/, fn ->
        Config.validate!(config)
      end
    end

    test "does not raise when default profile is :default" do
      config = Config.new(default_profile: :default)

      assert Config.validate!(config) == config
    end
  end
end
