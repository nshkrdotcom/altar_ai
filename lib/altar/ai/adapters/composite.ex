defmodule Altar.AI.Adapters.Composite do
  @moduledoc """
  Composite adapter that chains multiple providers with fallback logic.

  This adapter allows you to configure a chain of AI providers that will
  be tried in order until one succeeds. It supports retry logic and
  configurable error handling.

  ## Configuration

      config :altar_ai,
        adapters: %{
          composite: [
            providers: [
              {Altar.AI.Adapters.Gemini, []},
              {Altar.AI.Adapters.Claude, []},
              {Altar.AI.Adapters.Codex, []}
            ],
            fallback_on_error: true,
            max_retries: 3,
            retry_delay_ms: 1000,
            retry_on_types: [:rate_limit, :timeout, :network_error]
          ]
        }

  ## Examples

      # Will try Gemini first, then Claude if that fails, then Codex
      iex> Altar.AI.Adapters.Composite.generate("Hello")
      {:ok, %{content: "Hi!", provider: :gemini, ...}}

  """

  @behaviour Altar.AI.Behaviours.TextGen
  @behaviour Altar.AI.Behaviours.Embed
  @behaviour Altar.AI.Behaviours.Classify
  @behaviour Altar.AI.Behaviours.CodeGen

  alias Altar.AI.{Config, Error}

  @impl true
  def generate(prompt, opts \\ []) do
    execute_with_fallback(:generate, [prompt, opts], opts)
  end

  @impl true
  def stream(prompt, opts \\ []) do
    execute_with_fallback(:stream, [prompt, opts], opts)
  end

  @impl true
  def embed(text, opts \\ []) do
    execute_with_fallback(:embed, [text, opts], opts)
  end

  @impl true
  def batch_embed(texts, opts \\ []) do
    execute_with_fallback(:batch_embed, [texts, opts], opts)
  end

  @impl true
  def classify(text, labels, opts \\ []) do
    execute_with_fallback(:classify, [text, labels, opts], opts)
  end

  @impl true
  def generate_code(prompt, opts \\ []) do
    execute_with_fallback(:generate_code, [prompt, opts], opts)
  end

  @impl true
  def explain_code(code, opts \\ []) do
    execute_with_fallback(:explain_code, [code, opts], opts)
  end

  # Private implementation

  defp execute_with_fallback(function, args, opts) do
    config = Config.get_adapter_config(:composite)
    providers = Keyword.get(config, :providers, get_default_providers())
    max_retries = Keyword.get(opts, :max_retries, Keyword.get(config, :max_retries, 3))
    retry_delay_ms = Keyword.get(config, :retry_delay_ms, 1000)
    retry_on_types = Keyword.get(config, :retry_on_types, [:rate_limit, :timeout, :network_error])

    try_providers(providers, function, args, max_retries, retry_delay_ms, retry_on_types, [])
  end

  defp try_providers([], _function, _args, _max_retries, _retry_delay_ms, _retry_on_types, errors) do
    # All providers failed
    {:error,
     Error.new(
       :api_error,
       "All providers failed",
       :composite,
       details: %{errors: Enum.reverse(errors)}
     )}
  end

  defp try_providers(
         [{provider, provider_opts} | rest],
         function,
         args,
         max_retries,
         retry_delay_ms,
         retry_on_types,
         errors
       ) do
    case try_provider_with_retry(
           provider,
           provider_opts,
           function,
           args,
           max_retries,
           retry_delay_ms,
           retry_on_types
         ) do
      {:ok, result} ->
        # Success! Add provider info to metadata
        result_with_provider = add_provider_metadata(result, provider)
        {:ok, result_with_provider}

      {:error, error} ->
        # This provider failed, try the next one
        try_providers(rest, function, args, max_retries, retry_delay_ms, retry_on_types, [
          {provider, error} | errors
        ])
    end
  end

  defp try_provider_with_retry(
         provider,
         provider_opts,
         function,
         args,
         max_retries,
         retry_delay_ms,
         retry_on_types,
         attempt \\ 1
       ) do
    # Check if provider implements the function
    if function_exported?(provider, function, length(args)) do
      case apply(provider, function, args) do
        {:ok, result} ->
          {:ok, result}

        {:error, %Error{type: type}} = err ->
          should_retry = type in retry_on_types and attempt < max_retries

          if should_retry do
            Process.sleep(retry_delay_ms * attempt)

            try_provider_with_retry(
              provider,
              provider_opts,
              function,
              args,
              max_retries,
              retry_delay_ms,
              retry_on_types,
              attempt + 1
            )
          else
            err
          end

        {:error, _} = err ->
          err
      end
    else
      {:error,
       Error.new(
         :not_found,
         "Provider #{inspect(provider)} does not implement #{function}/#{length(args)}",
         :composite
       )}
    end
  end

  defp add_provider_metadata(result, provider) when is_map(result) do
    provider_name = extract_provider_name(provider)

    metadata =
      result
      |> Map.get(:metadata, %{})
      |> Map.put(:provider, provider_name)

    Map.put(result, :metadata, metadata)
  end

  defp add_provider_metadata(result, _provider), do: result

  defp extract_provider_name(provider) do
    case Atom.to_string(provider) do
      "Elixir.Altar.AI.Adapters." <> name -> String.downcase(name) |> String.to_atom()
      name -> String.to_atom(name)
    end
  end

  defp get_default_providers do
    [
      {Altar.AI.Adapters.Gemini, []},
      {Altar.AI.Adapters.Claude, []},
      {Altar.AI.Adapters.Codex, []}
    ]
  end
end
