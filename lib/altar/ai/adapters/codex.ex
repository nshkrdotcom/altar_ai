defmodule Altar.AI.Adapters.Codex do
  @moduledoc """
  Codex adapter for Altar.AI.

  This adapter wraps the `codex_sdk` package to provide TextGen and CodeGen
  capabilities through OpenAI's Codex API.

  ## Configuration

      config :altar_ai,
        adapters: %{
          codex: [
            api_key: {:system, "OPENAI_API_KEY"},
            model: "gpt-4"
          ]
        }

  ## Examples

      iex> Altar.AI.Adapters.Codex.generate("Hello", model: "gpt-4")
      {:ok, %{content: "Hi there!", model: "gpt-4", ...}}

      iex> Altar.AI.Adapters.Codex.generate_code("create a fibonacci function in elixir")
      {:ok, %{code: "def fib(n) when n < 2, do: n\\n...", language: "elixir", ...}}

  """

  @behaviour Altar.AI.Behaviours.TextGen
  @behaviour Altar.AI.Behaviours.CodeGen

  alias Altar.AI.{Config, Error, Response}

  @impl true
  def generate(prompt, opts \\ []) do
    if codex_available?() do
      generate_with_codex(prompt, opts)
    else
      {:error,
       Error.new(
         :not_found,
         "Codex SDK not available. Add {:codex_sdk, \"~> 0.1.0\"} to your deps.",
         :codex
       )}
    end
  end

  @impl true
  def stream(prompt, opts \\ []) do
    if codex_available?() do
      stream_with_codex(prompt, opts)
    else
      {:error,
       Error.new(
         :not_found,
         "Codex SDK not available. Add {:codex_sdk, \"~> 0.1.0\"} to your deps.",
         :codex
       )}
    end
  end

  @impl true
  def generate_code(prompt, opts \\ []) do
    if codex_available?() do
      generate_code_with_codex(prompt, opts)
    else
      {:error,
       Error.new(
         :not_found,
         "Codex SDK not available. Add {:codex_sdk, \"~> 0.1.0\"} to your deps.",
         :codex
       )}
    end
  end

  @impl true
  def explain_code(code, opts \\ []) do
    if codex_available?() do
      explain_code_with_codex(code, opts)
    else
      {:error,
       Error.new(
         :not_found,
         "Codex SDK not available. Add {:codex_sdk, \"~> 0.1.0\"} to your deps.",
         :codex
       )}
    end
  end

  # Private implementation

  defp codex_available? do
    Code.ensure_loaded?(Codex)
  end

  defp generate_with_codex(prompt, opts) do
    config = Config.get_adapter_config(:codex)
    model = Keyword.get(opts, :model, Keyword.get(config, :model, "gpt-4"))

    with {:ok, thread} <- Codex.start_thread(),
         {:ok, _message} <- Codex.Thread.add_message(thread, prompt),
         run_opts = build_run_opts(config, opts, model),
         {:ok, run} <- Codex.Thread.run(thread, run_opts),
         {:ok, messages} <- Codex.Thread.list_messages(thread) do
      response = extract_response(messages, run)
      {:ok, normalize_generate_response(response, model)}
    else
      {:error, error} -> {:error, normalize_error(error)}
    end
  end

  defp stream_with_codex(prompt, opts) do
    config = Config.get_adapter_config(:codex)
    model = Keyword.get(opts, :model, Keyword.get(config, :model, "gpt-4"))

    with {:ok, thread} <- Codex.start_thread(),
         {:ok, _message} <- Codex.Thread.add_message(thread, prompt),
         run_opts = build_run_opts(config, opts, model) |> Keyword.put(:stream, true),
         {:ok, stream} <- Codex.Thread.run(thread, run_opts) do
      normalized_stream =
        Stream.map(stream, fn event ->
          %{
            content: extract_event_content(event),
            delta: true,
            finish_reason: Map.get(event, :finish_reason)
          }
        end)

      {:ok, normalized_stream}
    else
      {:error, error} -> {:error, normalize_error(error)}
    end
  end

  defp generate_code_with_codex(prompt, opts) do
    language = Keyword.get(opts, :language, "elixir")

    enhanced_prompt =
      "Generate #{language} code for: #{prompt}\n\nProvide only the code without explanations."

    case generate_with_codex(enhanced_prompt, opts) do
      {:ok, response} ->
        code = extract_code_from_response(response.content)

        {:ok,
         %{
           code: code,
           language: language,
           explanation: nil,
           model: response.model,
           metadata: response.metadata
         }}

      error ->
        error
    end
  end

  defp explain_code_with_codex(code, opts) do
    language = Keyword.get(opts, :language)
    detail_level = Keyword.get(opts, :detail_level, :normal)

    prompt = build_explanation_prompt(code, language, detail_level)

    case generate_with_codex(prompt, opts) do
      {:ok, response} ->
        {:ok,
         %{
           explanation: response.content,
           language: language,
           complexity: nil,
           model: response.model,
           metadata: response.metadata
         }}

      error ->
        error
    end
  end

  defp build_run_opts(config, opts, model) do
    [
      model: model,
      api_key: Keyword.get(config, :api_key),
      temperature: Keyword.get(opts, :temperature),
      max_tokens: Keyword.get(opts, :max_tokens)
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp extract_response(messages, run) do
    latest_message = List.first(messages, %{})

    %{
      content: Map.get(latest_message, :content, ""),
      usage: Map.get(run, :usage, %{}),
      finish_reason: Map.get(run, :status)
    }
  end

  defp extract_event_content(%{delta: %{content: content}}), do: content
  defp extract_event_content(%{content: content}), do: content
  defp extract_event_content(_), do: ""

  defp extract_code_from_response(content) do
    # Remove markdown code blocks if present
    content
    |> String.replace(~r/```\w*\n/, "")
    |> String.replace(~r/```$/, "")
    |> String.trim()
  end

  defp build_explanation_prompt(code, language, detail_level) do
    lang_part = if language, do: " This is #{language} code.", else: ""

    detail_part =
      case detail_level do
        :brief ->
          " Provide a brief, one-paragraph explanation."

        :detailed ->
          " Provide a detailed explanation including algorithm analysis and complexity."

        _ ->
          " Provide a clear explanation of what this code does."
      end

    "Explain the following code:#{lang_part}#{detail_part}\n\n#{code}"
  end

  defp normalize_generate_response(response, model) do
    %{
      content: Response.extract_content(response),
      model: model,
      tokens: Response.normalize_tokens(Map.get(response, :usage, %{})),
      finish_reason: Response.normalize_finish_reason(Map.get(response, :finish_reason)),
      metadata: Response.extract_metadata(response)
    }
  end

  defp normalize_error(error) when is_binary(error) do
    Error.new(:api_error, error, :codex)
  end

  defp normalize_error(%{message: message, type: type}) do
    error_type = map_error_type(type)
    Error.new(error_type, message, :codex, retryable?: Error.retryable_by_default?(error_type))
  end

  defp normalize_error(%{message: message}) do
    Error.new(:api_error, message, :codex)
  end

  defp normalize_error(error) do
    Error.new(:api_error, inspect(error), :codex)
  end

  defp map_error_type("rate_limit_exceeded"), do: :rate_limit
  defp map_error_type("timeout"), do: :timeout
  defp map_error_type("invalid_request"), do: :validation_error
  defp map_error_type(_), do: :api_error
end
