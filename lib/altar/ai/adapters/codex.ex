defmodule Altar.AI.Adapters.Codex do
  @moduledoc """
  Codex/OpenAI adapter wrapping codex_sdk.

  Provides protocol implementations for OpenAI capabilities including
  text generation and code generation.
  """

  defstruct opts: []

  @type t :: %__MODULE__{opts: keyword()}

  def new(opts \\ []), do: %__MODULE__{opts: opts}

  @codex_available Code.ensure_loaded?(Codex)
  def available?, do: @codex_available
end

if Code.ensure_loaded?(Codex) do
  defimpl Altar.AI.Generator, for: Altar.AI.Adapters.Codex do
    alias Altar.AI.{Response, Error, Telemetry}

    def generate(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)

      Telemetry.span(:generate, %{provider: :codex}, fn ->
        with {:ok, thread} <- Codex.start_thread(merged_opts),
             {:ok, result} <- Codex.Thread.run(thread, prompt) do
          {:ok,
           %Response{
             content: extract_text(result.final_response),
             model: merged_opts[:model] || "gpt-4o",
             provider: :codex,
             finish_reason: :stop,
             tokens: Map.get(result, :usage, %{prompt: 0, completion: 0, total: 0})
           }}
        else
          {:error, error} -> {:error, Error.from_codex_error(error)}
        end
      end)
    end

    def stream(_adapter, _prompt, _opts) do
      {:error, Error.new(:unsupported, "Codex streaming not yet implemented", provider: :codex)}
    end

    defp extract_text(%{content: content}) when is_list(content) do
      content
      |> Enum.map(fn
        %{text: %{value: text}} -> text
        %{text: text} when is_binary(text) -> text
        _ -> ""
      end)
      |> Enum.join("\n")
    end

    defp extract_text(%{text: text}) when is_binary(text), do: text
    defp extract_text(text) when is_binary(text), do: text
    defp extract_text(_), do: ""
  end

  defimpl Altar.AI.CodeGenerator, for: Altar.AI.Adapters.Codex do
    alias Altar.AI.{CodeResult, Error, Telemetry}

    def generate_code(%{opts: opts}, prompt, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)

      Telemetry.span(:generate_code, %{provider: :codex}, fn ->
        with {:ok, thread} <- Codex.start_thread(merged_opts),
             {:ok, result} <- Codex.Thread.run(thread, "Generate code: #{prompt}") do
          code = extract_code(result.final_response)

          {:ok,
           %CodeResult{
             code: code,
             language: merged_opts[:language],
             metadata: %{model: merged_opts[:model] || "gpt-4o"}
           }}
        else
          {:error, error} -> {:error, Error.from_codex_error(error)}
        end
      end)
    end

    def explain_code(%{opts: opts}, code, call_opts) do
      merged_opts = Keyword.merge(opts, call_opts)

      Telemetry.span(:explain_code, %{provider: :codex}, fn ->
        with {:ok, thread} <- Codex.start_thread(merged_opts),
             {:ok, result} <- Codex.Thread.run(thread, "Explain this code:\n\n#{code}") do
          explanation = extract_text(result.final_response)
          {:ok, explanation}
        else
          {:error, error} -> {:error, Error.from_codex_error(error)}
        end
      end)
    end

    defp extract_code(response) do
      text = extract_text(response)

      # Try to extract code from markdown code blocks
      case Regex.run(~r/```(?:\w+\n)?(.*?)```/s, text) do
        [_, code] -> String.trim(code)
        _ -> text
      end
    end

    defp extract_text(%{content: content}) when is_list(content) do
      content
      |> Enum.map(fn
        %{text: %{value: text}} -> text
        %{text: text} when is_binary(text) -> text
        _ -> ""
      end)
      |> Enum.join("\n")
    end

    defp extract_text(%{text: text}) when is_binary(text), do: text
    defp extract_text(text) when is_binary(text), do: text
    defp extract_text(_), do: ""
  end
end
