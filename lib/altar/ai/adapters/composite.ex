defmodule Altar.AI.Adapters.Composite do
  @moduledoc """
  Composite adapter that tries multiple providers in sequence.

  This is where the real value of the protocol-based architecture shines.
  You can chain multiple adapters together with different fallback strategies.

  ## Examples

      # Fallback chain: try Gemini, then Claude, then OpenAI, then Codex, then fallback
      composite = Altar.AI.Adapters.Composite.new([
        Altar.AI.Adapters.Gemini.new(),
        Altar.AI.Adapters.Claude.new(),
        Altar.AI.Adapters.OpenAI.new(),
        Altar.AI.Adapters.Codex.new(),
        Altar.AI.Adapters.Fallback.new()
      ])

      # Or use the default chain based on available SDKs
      composite = Altar.AI.Adapters.Composite.default()
  """

  alias Altar.AI.Adapters.{Claude, Codex, Fallback, Gemini, OpenAI}

  defstruct [:providers, :strategy, opts: []]

  @type strategy :: :fallback | :round_robin | :random

  @type t :: %__MODULE__{
          providers: [struct()],
          strategy: strategy(),
          opts: keyword()
        }

  @doc """
  Create a new composite adapter.

  ## Options
    - `:strategy` - Strategy for selecting providers (`:fallback`, `:round_robin`, `:random`). Default: `:fallback`
  """
  def new(providers, opts \\ []) do
    %__MODULE__{
      providers: providers,
      strategy: Keyword.get(opts, :strategy, :fallback),
      opts: opts
    }
  end

  @doc """
  Create a composite with default provider chain based on available SDKs.

  Tries adapters in this order:
  1. Gemini (if available)
  2. Claude (if available)
  3. OpenAI (if available)
  4. Codex (if available)
  5. Fallback (always available)
  """
  def default do
    providers =
      []
      |> maybe_add(Gemini)
      |> maybe_add(Claude)
      |> maybe_add(OpenAI)
      |> maybe_add(Codex)
      |> Kernel.++([Fallback.new()])

    new(providers)
  end

  defp maybe_add(list, adapter_mod) do
    if adapter_mod.available?() do
      [adapter_mod.new() | list]
    else
      list
    end
  end

  @doc "Always available."
  def available?, do: true
end

defimpl Altar.AI.Generator, for: Altar.AI.Adapters.Composite do
  alias Altar.AI.{Capabilities, Generator, Telemetry}

  def generate(%{providers: providers, strategy: :fallback}, prompt, opts) do
    Telemetry.span(:generate, %{provider: :composite, strategy: :fallback}, fn ->
      run_fallback(providers, :generate, fn provider ->
        Generator.generate(provider, prompt, opts)
      end)
    end)
  end

  def generate(%{providers: providers, strategy: strategy}, prompt, opts) do
    case pick_provider(providers, :generate, strategy) do
      {:ok, provider} -> Generator.generate(provider, prompt, opts)
      :error -> {:error, Altar.AI.Error.new(:unavailable, "No providers support generation")}
    end
  end

  def stream(%{providers: providers, strategy: :fallback}, prompt, opts) do
    Telemetry.span(:stream, %{provider: :composite, strategy: :fallback}, fn ->
      run_fallback(providers, :stream, fn provider ->
        Generator.stream(provider, prompt, opts)
      end)
    end)
  end

  def stream(%{providers: providers, strategy: strategy}, prompt, opts) do
    case pick_provider(providers, :stream, strategy) do
      {:ok, provider} -> Generator.stream(provider, prompt, opts)
      :error -> {:error, Altar.AI.Error.new(:unavailable, "No providers support streaming")}
    end
  end

  defp pick_provider(providers, capability, :round_robin) do
    supporting = Enum.filter(providers, &Capabilities.supports?(&1, capability))

    case supporting do
      [] ->
        :error

      available ->
        idx = rem(:erlang.unique_integer([:positive]) - 1, length(available))
        {:ok, Enum.at(available, idx)}
    end
  end

  defp pick_provider(providers, capability, :random) do
    supporting = Enum.filter(providers, &Capabilities.supports?(&1, capability))

    case supporting do
      [] -> :error
      available -> {:ok, Enum.random(available)}
    end
  end

  defp pick_provider(providers, capability, _strategy) do
    case Enum.find(providers, &Capabilities.supports?(&1, capability)) do
      nil -> :error
      provider -> {:ok, provider}
    end
  end

  defp run_fallback(providers, capability, fun) do
    Enum.reduce_while(providers, {:error, :no_providers}, fn provider, _acc ->
      fallback_step(provider, capability, fun)
    end)
  end

  defp fallback_step(provider, capability, fun) do
    with true <- Capabilities.supports?(provider, capability),
         {:ok, _} = success <- fun.(provider) do
      {:halt, success}
    else
      false -> {:cont, {:error, :no_providers}}
      {:error, %{retryable?: true}} -> {:cont, {:error, :all_failed}}
      {:error, _} = error -> {:cont, error}
    end
  end
end

defimpl Altar.AI.Embedder, for: Altar.AI.Adapters.Composite do
  alias Altar.AI.{Capabilities, Embedder}

  def embed(%{providers: providers}, text, opts) do
    # Find first provider that implements Embedder
    provider = Enum.find(providers, &Capabilities.supports?(&1, :embed))

    if provider do
      Embedder.embed(provider, text, opts)
    else
      {:error, Altar.AI.Error.new(:unavailable, "No embedding provider available")}
    end
  end

  def batch_embed(%{providers: providers}, texts, opts) do
    # Find first provider that implements batch_embed
    provider = Enum.find(providers, &Capabilities.supports?(&1, :batch_embed))

    if provider do
      Embedder.batch_embed(provider, texts, opts)
    else
      {:error, Altar.AI.Error.new(:unavailable, "No batch embedding provider available")}
    end
  end
end

defimpl Altar.AI.Classifier, for: Altar.AI.Adapters.Composite do
  alias Altar.AI.{Capabilities, Classifier}

  def classify(%{providers: providers}, text, labels, opts) do
    provider = Enum.find(providers, &Capabilities.supports?(&1, :classify))

    if provider do
      Classifier.classify(provider, text, labels, opts)
    else
      {:error, Altar.AI.Error.new(:unavailable, "No classification provider available")}
    end
  end
end

defimpl Altar.AI.CodeGenerator, for: Altar.AI.Adapters.Composite do
  alias Altar.AI.{Capabilities, CodeGenerator}

  def generate_code(%{providers: providers}, prompt, opts) do
    provider = Enum.find(providers, &Capabilities.supports?(&1, :generate_code))

    if provider do
      CodeGenerator.generate_code(provider, prompt, opts)
    else
      {:error, Altar.AI.Error.new(:unavailable, "No code generation provider available")}
    end
  end

  def explain_code(%{providers: providers}, code, opts) do
    provider = Enum.find(providers, &Capabilities.supports?(&1, :explain_code))

    if provider do
      CodeGenerator.explain_code(provider, code, opts)
    else
      {:error, Altar.AI.Error.new(:unavailable, "No code explanation provider available")}
    end
  end
end
