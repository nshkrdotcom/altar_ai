defmodule Altar.AI.Integrations.FlowStone do
  @moduledoc """
  FlowStone integration module providing AI as a pipeline resource.

  This module can be used as a replacement for the `flowstone_ai` package,
  providing FlowStone pipelines with access to Altar.AI adapters.

  ## Usage in FlowStone Pipelines

      defmodule MyApp.Pipeline do
        use FlowStone.Pipeline

        resource :ai, Altar.AI.Integrations.FlowStone, []

        asset :classified_feedback do
          depends_on [:raw_feedback]
          requires [:ai]
          execute fn ctx, %{raw_feedback: feedback} ->
            Altar.AI.Integrations.FlowStone.classify_each(
              ctx.resources.ai,
              feedback,
              & &1.text,
              ["positive", "negative", "neutral"]
            )
          end
        end
      end

  ## DSL Helpers

  The module provides three main DSL helpers for batch operations:

    * `classify_each/5` - Classify multiple items
    * `enrich_each/4` - Enrich items with AI-generated content
    * `embed_each/4` - Generate embeddings for multiple items

  These helpers handle errors gracefully and preserve original item data.
  """

  alias __MODULE__.Telemetry, as: FlowStoneTelemetry
  alias Altar.AI.Adapters.Composite
  alias Altar.AI.Capabilities
  alias Altar.AI.Classifier
  alias Altar.AI.Embedder
  alias Altar.AI.Generator
  alias Altar.AI.Telemetry

  @type t :: %__MODULE__{
          adapter: term(),
          telemetry_metadata: map(),
          opts: keyword()
        }

  defstruct [:adapter, :telemetry_metadata, opts: []]

  @doc """
  Checks if this integration module is available.
  """
  @spec available?() :: boolean()
  def available?, do: true

  @doc """
  Set up telemetry bridge to forward altar_ai events to FlowStone's telemetry namespace.

  Should be called once during application startup.
  """
  @spec setup_telemetry() :: :ok
  def setup_telemetry do
    FlowStoneTelemetry.attach()
  end

  @doc """
  Initializes the FlowStone AI resource.

  ## Options

    * `:adapter` - The adapter to use. Can be:
      - An already-instantiated adapter struct (e.g., `Mock.new()`)
      - An adapter module (e.g., `Altar.AI.Adapters.Mock`) - will call `.new(adapter_opts)`
      - `nil` to use the default `Composite.default()`
    * `:adapter_opts` - Options passed to the adapter constructor when adapter is a module

  ## Examples

      {:ok, resource} = FlowStone.init([])
      {:ok, resource} = FlowStone.init(adapter: Altar.AI.Adapters.Gemini.new())
      {:ok, resource} = FlowStone.init(adapter: Altar.AI.Adapters.Mock, adapter_opts: [responses: %{}])
  """
  @spec init(keyword()) :: {:ok, t()} | {:error, term()}
  def init(opts \\ []) do
    # Support reading from application config (for flowstone_ai compatibility)
    config_adapter = get_flowstone_config(:adapter, nil)
    config_adapter_opts = get_flowstone_config(:adapter_opts, [])

    adapter_opts = Keyword.get(opts, :adapter_opts, config_adapter_opts)

    adapter =
      case Keyword.get(opts, :adapter, config_adapter) do
        nil ->
          Composite.default()

        adapter when is_atom(adapter) ->
          # Adapter is a module - instantiate it
          if adapter == Composite do
            Composite.default()
          else
            adapter.new(adapter_opts)
          end

        adapter ->
          # Already instantiated adapter struct
          adapter
      end

    telemetry_metadata =
      opts
      |> Keyword.get(:telemetry_metadata, %{})
      |> normalize_metadata()

    {:ok, %__MODULE__{adapter: adapter, telemetry_metadata: telemetry_metadata, opts: opts}}
  end

  # Read from flowstone_ai config for backward compatibility
  defp get_flowstone_config(key, default) do
    Application.get_env(:flowstone_ai, key, default)
  end

  @doc """
  FlowStone Resource setup callback.

  This is called by FlowStone during pipeline initialization.
  """
  @spec setup(keyword()) :: {:ok, t()} | {:error, term()}
  def setup(config), do: init(config)

  @doc """
  FlowStone Resource teardown callback.
  """
  @spec teardown(t()) :: :ok
  def teardown(_resource), do: :ok

  @doc """
  Checks the health of the AI resource.

  Returns `:healthy` if the adapter supports the `generate` capability.
  """
  @spec health_check(t()) :: :healthy | {:unhealthy, term()}
  def health_check(%__MODULE__{adapter: adapter}) do
    caps = Capabilities.capabilities(adapter)

    if caps.generate do
      :healthy
    else
      {:unhealthy, "Adapter does not support generation"}
    end
  end

  @doc """
  Generates text using the configured adapter.

  ## Examples

      {:ok, response} = FlowStone.generate(resource, "Hello world")
  """
  @spec generate(t(), String.t(), keyword()) :: {:ok, Altar.AI.Response.t()} | {:error, term()}
  def generate(%__MODULE__{} = resource, prompt, opts \\ []) do
    metadata =
      resource
      |> telemetry_metadata(opts)
      |> Map.put(:provider, adapter_name(resource.adapter))

    Telemetry.span(:generate, metadata, fn ->
      Generator.generate(resource.adapter, prompt, strip_telemetry_opts(opts))
    end)
  end

  @doc """
  Generates embeddings for text.

  ## Examples

      {:ok, embedding} = FlowStone.embed(resource, "Hello world")
  """
  @spec embed(t(), String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  def embed(%__MODULE__{} = resource, text, opts \\ []) do
    metadata =
      resource
      |> telemetry_metadata(opts)
      |> Map.put(:provider, adapter_name(resource.adapter))

    Telemetry.span(:embed, metadata, fn ->
      Embedder.embed(resource.adapter, text, strip_telemetry_opts(opts))
    end)
  end

  @doc """
  Generates batch embeddings for multiple texts.

  ## Examples

      {:ok, embeddings} = FlowStone.batch_embed(resource, ["Hello", "World"])
  """
  @spec batch_embed(t(), [String.t()], keyword()) :: {:ok, [[float()]]} | {:error, term()}
  def batch_embed(%__MODULE__{} = resource, texts, opts \\ []) do
    metadata =
      resource
      |> telemetry_metadata(opts)
      |> Map.merge(%{provider: adapter_name(resource.adapter), batch: true, count: length(texts)})

    Telemetry.span(:embed, metadata, fn ->
      Embedder.batch_embed(resource.adapter, texts, strip_telemetry_opts(opts))
    end)
  end

  @doc """
  Classifies text into one of the given labels.

  ## Examples

      {:ok, result} = FlowStone.classify(resource, "Great product!", ["positive", "negative"])
  """
  @spec classify(t(), String.t(), [String.t()], keyword()) ::
          {:ok, Altar.AI.Classification.t()} | {:error, term()}
  def classify(%__MODULE__{} = resource, text, labels, opts \\ []) do
    metadata =
      resource
      |> telemetry_metadata(opts)
      |> Map.merge(%{provider: adapter_name(resource.adapter), label_count: length(labels)})

    Telemetry.span(:classify, metadata, fn ->
      Classifier.classify(resource.adapter, text, labels, strip_telemetry_opts(opts))
    end)
  end

  @doc """
  Returns the capabilities of the configured adapter.

  ## Examples

      caps = FlowStone.capabilities(resource)
      caps.generate  #=> true
  """
  @spec capabilities(t()) :: Capabilities.capability_map()
  def capabilities(%__MODULE__{adapter: adapter}) do
    Capabilities.capabilities(adapter)
  end

  # DSL Helpers

  @doc """
  Classifies multiple items and adds classification results to each item.

  Each item will have `:classification` and `:confidence` keys added.
  Items that fail classification will have `:classification` set to `:unknown`.

  ## Parameters

    * `resource` - The FlowStone AI resource
    * `items` - List of items to classify
    * `text_fn` - Function to extract text from each item
    * `labels` - List of classification labels
    * `opts` - Additional options passed to the classifier

  ## Examples

      {:ok, results} = classify_each(resource, items, & &1.text, ["positive", "negative"])
  """
  @spec classify_each(t(), [map()], (map() -> String.t()), [String.t()], keyword()) ::
          {:ok, [map()]}
  def classify_each(resource, items, text_fn, labels, opts \\ []) do
    results =
      Enum.map(items, fn item ->
        text = text_fn.(item)

        case classify(resource, text, labels, opts) do
          {:ok, classification} ->
            item
            |> Map.put(:classification, classification.label)
            |> Map.put(:confidence, classification.confidence)

          {:error, _} ->
            item
            |> Map.put(:classification, :unknown)
            |> Map.put(:confidence, 0.0)
        end
      end)

    {:ok, results}
  end

  defp telemetry_metadata(%__MODULE__{telemetry_metadata: base}, opts) do
    metadata =
      base
      |> Map.merge(normalize_metadata(Keyword.get(opts, :telemetry_metadata, %{})))
      |> Map.merge(extract_command_metadata(opts))

    maybe_put(metadata, :model, Keyword.get(opts, :model))
  end

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(metadata) when is_list(metadata), do: Map.new(metadata)
  defp normalize_metadata(_), do: %{}

  defp extract_command_metadata(opts) do
    [:command_session_id, :command_workflow_id, :command_user_id, :correlation_id, :request_id]
    |> Enum.reduce(%{}, fn key, acc ->
      case Keyword.get(opts, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp strip_telemetry_opts(opts), do: Keyword.delete(opts, :telemetry_metadata)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Enriches multiple items with AI-generated content.

  Each item will have an `:ai_enrichment` key added with the generated content.
  Items that fail enrichment will not have the key added.

  ## Parameters

    * `resource` - The FlowStone AI resource
    * `items` - List of items to enrich
    * `prompt_fn` - Function to generate a prompt from each item
    * `opts` - Additional options passed to the generator

  ## Examples

      {:ok, results} = enrich_each(resource, items, fn item -> "Summarize: \#{item.text}" end)
  """
  @spec enrich_each(t(), [map()], (map() -> String.t()), keyword()) :: {:ok, [map()]}
  def enrich_each(resource, items, prompt_fn, opts \\ []) do
    results =
      Enum.map(items, fn item ->
        prompt = prompt_fn.(item)

        case generate(resource, prompt, opts) do
          {:ok, response} ->
            Map.put(item, :ai_enrichment, response.content)

          {:error, _} ->
            item
        end
      end)

    {:ok, results}
  end

  @doc """
  Generates embeddings for multiple items using batch embedding.

  Each item will have an `:embedding` key added with the embedding vector.
  Unlike `classify_each` and `enrich_each`, this function propagates errors
  because batch embedding is an all-or-nothing operation.

  ## Parameters

    * `resource` - The FlowStone AI resource
    * `items` - List of items to embed
    * `text_fn` - Function to extract text from each item
    * `opts` - Additional options passed to the embedder

  ## Examples

      {:ok, results} = embed_each(resource, items, & &1.text)
  """
  @spec embed_each(t(), [map()], (map() -> String.t()), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def embed_each(resource, items, text_fn, opts \\ [])

  def embed_each(_resource, [], _text_fn, _opts) do
    {:ok, []}
  end

  def embed_each(resource, items, text_fn, opts) do
    texts = Enum.map(items, text_fn)

    case batch_embed(resource, texts, opts) do
      {:ok, embeddings} ->
        results =
          items
          |> Enum.zip(embeddings)
          |> Enum.map(fn {item, embedding} ->
            Map.put(item, :embedding, embedding)
          end)

        {:ok, results}

      {:error, _} = error ->
        error
    end
  end

  # Private helpers

  defp adapter_name(adapter) when is_struct(adapter) do
    adapter.__struct__
    |> Module.split()
    |> List.last()
    |> String.downcase()
    |> String.to_atom()
  end

  defp adapter_name(_), do: :unknown
end
