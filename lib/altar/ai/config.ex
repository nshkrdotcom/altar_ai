defmodule Altar.AI.Config do
  @moduledoc """
  Configuration management for Altar.AI.

  Provides a profile-based configuration system that supports:
  - Named profiles with provider-specific settings
  - Global options that apply to all profiles
  - System prompt management with precedence rules
  - Retry configuration with sensible defaults

  ## Example

      config = Config.new(
        default_profile: :gemini,
        global_opts: [timeout: 30_000, max_retries: 3]
      )
      |> Config.add_profile(:gemini,
        adapter: Altar.AI.Adapters.Gemini,
        model: "gemini-pro",
        api_key: System.get_env("GEMINI_API_KEY"),
        system_prompt: "You are a helpful assistant."
      )
      |> Config.add_profile(:claude,
        adapter: Altar.AI.Adapters.Claude,
        model: "claude-3-opus",
        api_key: System.get_env("CLAUDE_API_KEY")
      )

  ## Configuration Precedence

  When resolving options for a request, the precedence is (highest to lowest):
  1. Call-time options passed to the operation
  2. Profile-specific options
  3. Global options
  """

  @type profile_name :: atom()
  @type profile_opts :: keyword()
  @type adapter :: module() | struct()

  @type t :: %__MODULE__{
          default_profile: profile_name(),
          profiles: %{profile_name() => profile_opts()},
          global_opts: keyword()
        }

  defstruct default_profile: :default,
            profiles: %{},
            global_opts: []

  @default_retry_config [
    max_attempts: 3,
    base_delay_ms: 500,
    max_delay_ms: 10_000,
    jitter: true
  ]

  @doc """
  Creates a new Config struct with the given options.

  ## Options

    * `:default_profile` - The default profile to use when none is specified (default: `:default`)
    * `:profiles` - A map of profile names to their options (default: `%{}`)
    * `:global_opts` - Options that apply to all profiles (default: `[]`)

  ## Examples

      Config.new()
      Config.new(default_profile: :gemini)
      Config.new(profiles: %{gemini: [model: "gemini-pro"]})
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      default_profile: Keyword.get(opts, :default_profile, :default),
      profiles: Keyword.get(opts, :profiles, %{}),
      global_opts: Keyword.get(opts, :global_opts, [])
    }
  end

  @doc """
  Adds or updates a profile in the config.

  ## Examples

      config
      |> Config.add_profile(:gemini, model: "gemini-pro", api_key: "key")
  """
  @spec add_profile(t(), profile_name(), profile_opts()) :: t()
  def add_profile(%__MODULE__{} = config, name, opts) when is_atom(name) and is_list(opts) do
    %{config | profiles: Map.put(config.profiles, name, opts)}
  end

  @doc """
  Gets the options for a specific profile.

  Returns `nil` if the profile does not exist.

  ## Examples

      Config.get_profile(config, :gemini)
      #=> [model: "gemini-pro", api_key: "key"]
  """
  @spec get_profile(t(), profile_name()) :: profile_opts() | nil
  def get_profile(%__MODULE__{profiles: profiles}, name) do
    Map.get(profiles, name)
  end

  @doc """
  Resolves options for a request by merging global, profile, and call-time options.

  The precedence is (highest to lowest):
  1. Call-time options
  2. Profile options
  3. Global options

  When the profile is `:default`, it resolves to the configured default profile.

  ## Examples

      Config.resolve_opts(config, :gemini)
      Config.resolve_opts(config, :gemini, temperature: 0.9)
  """
  @spec resolve_opts(t(), profile_name(), keyword()) :: keyword()
  def resolve_opts(%__MODULE__{} = config, profile, call_opts \\ []) do
    resolved_profile =
      if profile == :default do
        config.default_profile
      else
        profile
      end

    profile_opts = get_profile(config, resolved_profile) || []

    config.global_opts
    |> Keyword.merge(profile_opts)
    |> Keyword.merge(call_opts)
  end

  @doc """
  Loads configuration from the application environment.

  Reads from the `:altar_ai` application:
    * `:default_profile` - Default profile name
    * `:profiles` - Map of profile configurations
    * `:global_opts` - Global options

  ## Examples

      config = Config.from_application_env()
  """
  @spec from_application_env(atom()) :: t()
  def from_application_env(app \\ :altar_ai) do
    new(
      default_profile: Application.get_env(app, :default_profile, :default),
      profiles: Application.get_env(app, :profiles, %{}),
      global_opts: Application.get_env(app, :global_opts, [])
    )
  end

  @doc """
  Gets the adapter module for a profile.

  Returns `nil` if the profile doesn't exist or has no adapter configured.

  ## Examples

      Config.get_adapter(config, :gemini)
      #=> Altar.AI.Adapters.Gemini
  """
  @spec get_adapter(t(), profile_name()) :: adapter() | nil
  def get_adapter(%__MODULE__{} = config, profile) do
    case get_profile(config, profile) do
      nil -> nil
      opts -> Keyword.get(opts, :adapter)
    end
  end

  @doc """
  Gets the system prompt for a profile.

  Checks the profile first, then falls back to global options.
  Returns `nil` if no system prompt is configured.

  ## Examples

      Config.system_prompt(config, :gemini)
      #=> "You are a helpful assistant."
  """
  @spec system_prompt(t(), profile_name()) :: String.t() | nil
  def system_prompt(%__MODULE__{} = config, profile) do
    profile_opts = get_profile(config, profile) || []
    profile_prompt = Keyword.get(profile_opts, :system_prompt)

    profile_prompt || Keyword.get(config.global_opts, :system_prompt)
  end

  @doc """
  Gets the retry configuration for a profile.

  Returns the profile's retry config merged with defaults.

  ## Default Retry Config

    * `:max_attempts` - 3
    * `:base_delay_ms` - 500
    * `:max_delay_ms` - 10_000
    * `:jitter` - true

  ## Examples

      Config.retry_config(config, :gemini)
      #=> [max_attempts: 5, base_delay_ms: 1000, max_delay_ms: 10_000, jitter: true]
  """
  @spec retry_config(t(), profile_name()) :: keyword()
  def retry_config(%__MODULE__{} = config, profile) do
    profile_opts = get_profile(config, profile) || []
    profile_retry = Keyword.get(profile_opts, :retry, [])

    Keyword.merge(@default_retry_config, profile_retry)
  end

  @doc """
  Validates the configuration.

  Raises `ArgumentError` if the configuration is invalid.

  ## Validations

    * Default profile must be `:default` or exist in profiles

  ## Examples

      Config.validate!(config)  # Returns config if valid
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    validate_default_profile!(config)
    config
  end

  defp validate_default_profile!(%{default_profile: :default}), do: :ok

  defp validate_default_profile!(%{default_profile: profile, profiles: profiles}) do
    unless Map.has_key?(profiles, profile) do
      raise ArgumentError, "default profile #{inspect(profile)} is not defined in profiles"
    end
  end
end
