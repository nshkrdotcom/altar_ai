defmodule Altar.AI.Adapters.Mock do
  @moduledoc """
  Mock adapter for testing - configurable responses.

  Allows you to configure specific responses for different operations,
  making it ideal for testing without calling real AI services.
  """

  defstruct [:responses, :call_log, opts: []]

  @type t :: %__MODULE__{
          responses: map(),
          call_log: list(),
          opts: keyword()
        }

  @doc """
  Create a new mock adapter.

  ## Examples

      iex> mock = Altar.AI.Adapters.Mock.new()
      iex> mock = Altar.AI.Adapters.Mock.with_response(mock, :generate, {:ok, %Altar.AI.Response{content: "test"}})
  """
  def new(opts \\ []) do
    responses = Keyword.get(opts, :responses, %{})
    %__MODULE__{responses: responses, call_log: [], opts: opts}
  end

  @doc """
  Configure a response for a specific operation.
  """
  def with_response(mock, operation, response) do
    %{mock | responses: Map.put(mock.responses, operation, response)}
  end

  @doc """
  Always available.
  """
  def available?, do: true
end

defimpl Altar.AI.Generator, for: Altar.AI.Adapters.Mock do
  alias Altar.AI.Response

  def generate(%{responses: responses}, prompt, opts) do
    case Map.get(responses, :generate) do
      nil ->
        {:ok, %Response{content: "Mock response for: #{prompt}", provider: :mock, model: "mock"}}

      {:ok, _} = resp ->
        resp

      {:error, _} = err ->
        err

      fun when is_function(fun, 2) ->
        fun.(prompt, opts)

      fun when is_function(fun, 1) ->
        fun.(prompt)
    end
  end

  def stream(%{responses: responses}, prompt, _opts) do
    case Map.get(responses, :stream) do
      nil ->
        # Return a simple mock stream
        {:ok, Stream.map([prompt], fn p -> "Mock stream for: #{p}" end)}

      {:ok, _} = resp ->
        resp

      {:error, _} = err ->
        err

      fun when is_function(fun, 1) ->
        fun.(prompt)
    end
  end
end

defimpl Altar.AI.Embedder, for: Altar.AI.Adapters.Mock do
  def embed(%{responses: responses}, text, _opts) do
    case Map.get(responses, :embed) do
      nil ->
        # Return a mock embedding vector (256 dimensions)
        {:ok, Enum.map(1..256, fn _ -> :rand.uniform() end)}

      {:ok, _} = resp ->
        resp

      {:error, _} = err ->
        err

      fun when is_function(fun, 1) ->
        fun.(text)
    end
  end

  def batch_embed(%{responses: responses} = mock, texts, opts) do
    case Map.get(responses, :batch_embed) do
      nil ->
        # Return mock embeddings for each text
        {:ok,
         Enum.map(texts, fn _ ->
           {:ok, vec} = embed(mock, "", opts)
           vec
         end)}

      {:ok, _} = resp ->
        resp

      {:error, _} = err ->
        err

      fun when is_function(fun, 1) ->
        fun.(texts)
    end
  end
end

defimpl Altar.AI.Classifier, for: Altar.AI.Adapters.Mock do
  alias Altar.AI.Classification

  def classify(%{responses: responses}, text, labels, opts) do
    case Map.get(responses, :classify) do
      nil ->
        # Simple mock: pick first label with high confidence
        {:ok, Classification.new(List.first(labels), 0.95, %{List.first(labels) => 0.95})}

      {:ok, _} = resp ->
        resp

      {:error, _} = err ->
        err

      fun when is_function(fun, 3) ->
        fun.(text, labels, opts)

      fun when is_function(fun, 2) ->
        fun.(text, labels)
    end
  end
end

defimpl Altar.AI.CodeGenerator, for: Altar.AI.Adapters.Mock do
  alias Altar.AI.CodeResult

  def generate_code(%{responses: responses}, prompt, _opts) do
    case Map.get(responses, :generate_code) do
      nil ->
        {:ok, %CodeResult{code: "# Mock code for: #{prompt}", language: "elixir"}}

      {:ok, _} = resp ->
        resp

      {:error, _} = err ->
        err

      fun when is_function(fun, 1) ->
        fun.(prompt)
    end
  end

  def explain_code(%{responses: responses}, code, _opts) do
    case Map.get(responses, :explain_code) do
      nil ->
        {:ok, "Mock explanation for code: #{String.slice(code, 0, 50)}..."}

      {:ok, _} = resp ->
        resp

      {:error, _} = err ->
        err

      fun when is_function(fun, 1) ->
        fun.(code)
    end
  end
end
