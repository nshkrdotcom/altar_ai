defmodule Altar.AI.Config do
  @moduledoc """
  Configuration management for Altar.AI.

  This module provides utilities for retrieving and validating configuration
  for AI providers and adapters.

  ## Configuration

  Configuration is stored under the `:altar_ai` application key:

      config :altar_ai,
        default_adapter: Altar.AI.Adapters.Gemini,
        adapters: %{
          gemini: [
            api_key: {:system, "GEMINI_API_KEY"},
            model: "gemini-pro"
          ],
          claude: [
            api_key: {:system, "ANTHROPIC_API_KEY"},
            model: "claude-3-opus-20240229"
          ],
          composite: [
            providers: [:gemini, :claude],
            fallback_on_error: true,
            max_retries: 3
          ]
        }

  ## Examples

      iex> Altar.AI.Config.get_adapter()
      Altar.AI.Adapters.Gemini

      iex> Altar.AI.Config.get_adapter_config(:gemini)
      [api_key: "...", model: "gemini-pro"]

  """

  @doc """
  Gets the default adapter module.

  Returns the configured default adapter or falls back to the Mock adapter
  if none is configured.

  ## Examples

      iex> Altar.AI.Config.get_adapter()
      Altar.AI.Adapters.Gemini

  """
  @spec get_adapter() :: module()
  def get_adapter do
    Application.get_env(:altar_ai, :default_adapter, Altar.AI.Adapters.Mock)
  end

  @doc """
  Gets configuration for a specific adapter.

  ## Parameters

    * `adapter` - Adapter name (atom) or module

  ## Examples

      iex> Altar.AI.Config.get_adapter_config(:gemini)
      [api_key: "...", model: "gemini-pro"]

  """
  @spec get_adapter_config(atom() | module()) :: keyword()
  def get_adapter_config(adapter) when is_atom(adapter) do
    adapter_name = adapter_to_name(adapter)

    :altar_ai
    |> Application.get_env(:adapters, %{})
    |> Map.get(adapter_name, [])
    |> resolve_config()
  end

  @doc """
  Gets a specific configuration value for an adapter.

  ## Parameters

    * `adapter` - Adapter name (atom) or module
    * `key` - Configuration key
    * `default` - Default value if not found

  ## Examples

      iex> Altar.AI.Config.get_adapter_value(:gemini, :model, "gemini-pro")
      "gemini-2.0-flash-exp"

  """
  @spec get_adapter_value(atom() | module(), atom(), any()) :: any()
  def get_adapter_value(adapter, key, default \\ nil) do
    adapter
    |> get_adapter_config()
    |> Keyword.get(key, default)
  end

  @doc """
  Gets all configured adapters.

  ## Examples

      iex> Altar.AI.Config.get_all_adapters()
      [:gemini, :claude, :codex]

  """
  @spec get_all_adapters() :: [atom()]
  def get_all_adapters do
    :altar_ai
    |> Application.get_env(:adapters, %{})
    |> Map.keys()
  end

  # Private helpers

  defp adapter_to_name(adapter) when is_atom(adapter) do
    case Atom.to_string(adapter) do
      "Elixir.Altar.AI.Adapters." <> name ->
        name
        |> String.downcase()
        |> String.to_atom()

      name ->
        String.to_atom(name)
    end
  end

  defp resolve_config(config) when is_list(config) do
    Enum.map(config, fn
      {key, {:system, env_var}} ->
        {key, System.get_env(env_var)}

      {key, {:system, env_var, default}} ->
        {key, System.get_env(env_var, default)}

      other ->
        other
    end)
  end

  defp resolve_config(config), do: config
end
