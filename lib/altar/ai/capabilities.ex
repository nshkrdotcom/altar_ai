defmodule Altar.AI.Capabilities do
  @moduledoc """
  Runtime capability detection for adapters.

  Since we use protocols, we can introspect at runtime which capabilities
  each adapter supports. This is more flexible than compile-time behaviours.
  """

  @type t :: %{
          generate: boolean(),
          stream: boolean(),
          embed: boolean(),
          batch_embed: boolean(),
          classify: boolean(),
          generate_code: boolean(),
          explain_code: boolean()
        }

  @type capability_map :: t()

  @protocols %{
    generate: {Altar.AI.Generator, :generate},
    stream: {Altar.AI.Generator, :stream},
    embed: {Altar.AI.Embedder, :embed},
    batch_embed: {Altar.AI.Embedder, :batch_embed},
    classify: {Altar.AI.Classifier, :classify},
    generate_code: {Altar.AI.CodeGenerator, :generate_code},
    explain_code: {Altar.AI.CodeGenerator, :explain_code}
  }

  @doc """
  Check if adapter supports a specific capability.

  ## Examples

      iex> gemini = Altar.AI.Adapters.Gemini.new()
      iex> Altar.AI.Capabilities.supports?(gemini, :generate)
      true

      iex> Altar.AI.Capabilities.supports?(gemini, :classify)
      false
  """
  def supports?(adapter, capability) when is_atom(capability) do
    case @protocols[capability] do
      {protocol, _function} ->
        impl = protocol.impl_for(adapter)
        impl != nil

      nil ->
        false
    end
  end

  @doc """
  Get all capabilities supported by an adapter.

  ## Examples

      iex> gemini = Altar.AI.Adapters.Gemini.new()
      iex> Altar.AI.Capabilities.list(gemini)
      [:generate, :stream, :embed, :batch_embed]
  """
  def list(adapter) do
    @protocols
    |> Map.keys()
    |> Enum.filter(&supports?(adapter, &1))
  end

  @doc """
  Get detailed capability map for an adapter.

  ## Examples

      iex> gemini = Altar.AI.Adapters.Gemini.new()
      iex> Altar.AI.Capabilities.capabilities(gemini)
      %{
        generate: true,
        stream: true,
        embed: true,
        batch_embed: true,
        classify: false,
        generate_code: false,
        explain_code: false
      }
  """
  def capabilities(adapter) do
    %{
      generate: supports?(adapter, :generate),
      stream: supports?(adapter, :stream),
      embed: supports?(adapter, :embed),
      batch_embed: supports?(adapter, :batch_embed),
      classify: supports?(adapter, :classify),
      generate_code: supports?(adapter, :generate_code),
      explain_code: supports?(adapter, :explain_code)
    }
  end

  @doc """
  Get a human-readable description of adapter capabilities.

  ## Examples

      iex> gemini = Altar.AI.Adapters.Gemini.new()
      iex> Altar.AI.Capabilities.describe(gemini)
      "Gemini: text generation, streaming, embeddings"
  """
  def describe(adapter) do
    provider = provider_name(adapter)
    caps = list(adapter)

    descriptions = Enum.map_join(caps, ", ", &capability_description/1)

    "#{provider}: #{descriptions}"
  end

  defp provider_name(%{__struct__: module}) do
    module
    |> Module.split()
    |> List.last()
  end

  defp capability_description(:generate), do: "text generation"
  defp capability_description(:stream), do: "streaming"
  defp capability_description(:embed), do: "embeddings"
  defp capability_description(:batch_embed), do: "batch embeddings"
  defp capability_description(:classify), do: "classification"
  defp capability_description(:generate_code), do: "code generation"
  defp capability_description(:explain_code), do: "code explanation"
  defp capability_description(cap), do: to_string(cap)
end
