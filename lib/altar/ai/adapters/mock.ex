defmodule Altar.AI.Adapters.Mock do
  @moduledoc """
  Mock adapter for testing and development.

  This adapter provides configurable responses and tracks all calls,
  making it ideal for testing applications that use Altar.AI without
  making real API calls.

  ## Configuration

      config :altar_ai,
        adapters: %{
          mock: [
            responses: %{
              generate: {:ok, %{content: "Mocked response", model: "mock-model", ...}},
              embed: {:ok, %{vector: [0.1, 0.2, 0.3], model: "mock-embed", ...}}
            },
            track_calls: true
          ]
        }

  ## Examples

      # Configure a response
      iex> Altar.AI.Adapters.Mock.set_response(:generate, {:ok, %{content: "Test"}})
      :ok

      # Make a call
      iex> Altar.AI.Adapters.Mock.generate("Hello")
      {:ok, %{content: "Test", ...}}

      # Check call history
      iex> Altar.AI.Adapters.Mock.get_calls()
      [{:generate, ["Hello", []]}]

  """

  @behaviour Altar.AI.Behaviours.TextGen
  @behaviour Altar.AI.Behaviours.Embed
  @behaviour Altar.AI.Behaviours.Classify
  @behaviour Altar.AI.Behaviours.CodeGen

  use Agent

  alias Altar.AI.Config

  @default_generate_response %{
    content: "This is a mocked response from Altar.AI Mock adapter.",
    model: "mock-model",
    tokens: %{prompt: 10, completion: 20, total: 30},
    finish_reason: :stop,
    metadata: %{}
  }

  @default_embed_response %{
    vector: Enum.map(1..768, fn _ -> :rand.uniform() end),
    model: "mock-embed",
    dimensions: 768,
    metadata: %{}
  }

  @default_classify_response %{
    label: "positive",
    confidence: 0.95,
    scores: %{"positive" => 0.95, "negative" => 0.05},
    metadata: %{}
  }

  @default_code_response %{
    code: "def example, do: :mock",
    language: "elixir",
    explanation: "This is a mock code example.",
    model: "mock-code",
    metadata: %{}
  }

  @default_explain_response %{
    explanation: "This is a mock explanation of the code.",
    language: "elixir",
    complexity: :simple,
    model: "mock-code",
    metadata: %{}
  }

  # Client API

  def start_link(_opts \\ []) do
    Agent.start_link(
      fn ->
        %{
          responses: %{},
          calls: []
        }
      end,
      name: __MODULE__
    )
  end

  @doc """
  Sets a mock response for a specific function.

  ## Examples

      iex> Altar.AI.Adapters.Mock.set_response(:generate, {:ok, %{content: "Test"}})
      :ok

  """
  def set_response(function, response) do
    ensure_started()

    Agent.update(__MODULE__, fn state ->
      %{state | responses: Map.put(state.responses, function, response)}
    end)
  end

  @doc """
  Gets all recorded calls.

  ## Examples

      iex> Altar.AI.Adapters.Mock.get_calls()
      [{:generate, ["Hello", []]}, {:embed, ["Test", []]}]

  """
  def get_calls do
    ensure_started()
    Agent.get(__MODULE__, fn state -> Enum.reverse(state.calls) end)
  end

  @doc """
  Gets calls for a specific function.

  ## Examples

      iex> Altar.AI.Adapters.Mock.get_calls(:generate)
      [["Hello", []], ["World", []]]

  """
  def get_calls(function) do
    ensure_started()

    Agent.get(__MODULE__, fn state ->
      state.calls
      |> Enum.filter(fn {f, _args} -> f == function end)
      |> Enum.map(fn {_f, args} -> args end)
      |> Enum.reverse()
    end)
  end

  @doc """
  Clears all recorded calls.
  """
  def clear_calls do
    ensure_started()
    Agent.update(__MODULE__, fn state -> %{state | calls: []} end)
  end

  @doc """
  Resets all responses and calls.
  """
  def reset do
    ensure_started()
    Agent.update(__MODULE__, fn _state -> %{responses: %{}, calls: []} end)
  end

  # Behaviour implementations

  @impl true
  def generate(prompt, opts \\ []) do
    track_call(:generate, [prompt, opts])
    get_response(:generate, {:ok, @default_generate_response})
  end

  @impl true
  def stream(prompt, opts \\ []) do
    track_call(:stream, [prompt, opts])

    case get_response(:stream, {:ok, @default_generate_response}) do
      {:ok, response} when is_map(response) ->
        # Convert response to stream
        stream =
          Stream.map([response], fn resp ->
            %{content: resp.content, delta: false, finish_reason: :stop}
          end)

        {:ok, stream}

      other ->
        other
    end
  end

  @impl true
  def embed(text, opts \\ []) do
    track_call(:embed, [text, opts])
    get_response(:embed, {:ok, @default_embed_response})
  end

  @impl true
  def batch_embed(texts, opts \\ []) do
    track_call(:batch_embed, [texts, opts])

    case get_response(:batch_embed, {:ok, @default_embed_response}) do
      {:ok, response} when is_map(response) ->
        # Generate vectors for each text
        vectors = Enum.map(texts, fn _ -> response.vector end)

        {:ok,
         %{
           vectors: vectors,
           model: response.model,
           dimensions: response.dimensions,
           metadata: response.metadata
         }}

      other ->
        other
    end
  end

  @impl true
  def classify(text, labels, opts \\ []) do
    track_call(:classify, [text, labels, opts])

    # Generate realistic scores for provided labels
    case get_response(:classify, {:ok, @default_classify_response}) do
      {:ok, response} when is_map(response) ->
        first_label = List.first(labels, "unknown")
        total = Enum.count(labels)
        primary_score = 0.95
        remaining_score = (1.0 - primary_score) / max(total - 1, 1)

        scores =
          labels
          |> Enum.with_index()
          |> Enum.map(fn {label, idx} ->
            {label, if(idx == 0, do: primary_score, else: remaining_score)}
          end)
          |> Enum.into(%{})

        {:ok,
         %{
           label: first_label,
           confidence: primary_score,
           scores: scores,
           metadata: response.metadata
         }}

      other ->
        other
    end
  end

  @impl true
  def generate_code(prompt, opts \\ []) do
    track_call(:generate_code, [prompt, opts])
    get_response(:generate_code, {:ok, @default_code_response})
  end

  @impl true
  def explain_code(code, opts \\ []) do
    track_call(:explain_code, [code, opts])
    get_response(:explain_code, {:ok, @default_explain_response})
  end

  # Private helpers

  defp ensure_started do
    unless Process.whereis(__MODULE__) do
      start_link()
    end
  end

  defp track_call(function, args) do
    config = Config.get_adapter_config(:mock)

    if Keyword.get(config, :track_calls, true) do
      ensure_started()

      Agent.update(__MODULE__, fn state ->
        %{state | calls: [{function, args} | state.calls]}
      end)
    end
  end

  defp get_response(function, default) do
    ensure_started()
    config = Config.get_adapter_config(:mock)

    # Check config responses first
    config_response = get_in(config, [:responses, function])

    # Then check runtime responses
    runtime_response = Agent.get(__MODULE__, fn state -> Map.get(state.responses, function) end)

    runtime_response || config_response || default
  end
end
