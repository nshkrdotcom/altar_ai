defmodule Altar.AI.Response do
  @moduledoc """
  Utilities for normalizing and handling AI provider responses.

  This module provides helpers for converting provider-specific response
  formats into the normalized formats expected by Altar.AI behaviours.
  """

  @doc """
  Normalizes token usage information from various formats.

  ## Examples

      iex> Altar.AI.Response.normalize_tokens(%{input: 10, output: 20})
      %{prompt: 10, completion: 20, total: 30}

      iex> Altar.AI.Response.normalize_tokens(%{prompt_tokens: 5, completion_tokens: 15})
      %{prompt: 5, completion: 15, total: 20}

  """
  @spec normalize_tokens(map()) :: %{
          prompt: non_neg_integer(),
          completion: non_neg_integer(),
          total: non_neg_integer()
        }
  def normalize_tokens(tokens) when is_map(tokens) do
    prompt = get_token_count(tokens, [:prompt, :prompt_tokens, :input, :input_tokens])

    completion =
      get_token_count(tokens, [:completion, :completion_tokens, :output, :output_tokens])

    %{
      prompt: prompt,
      completion: completion,
      total: prompt + completion
    }
  end

  def normalize_tokens(_), do: %{prompt: 0, completion: 0, total: 0}

  @doc """
  Normalizes finish reason from various provider formats.

  ## Examples

      iex> Altar.AI.Response.normalize_finish_reason("STOP")
      :stop

      iex> Altar.AI.Response.normalize_finish_reason(:max_tokens)
      :length

  """
  @spec normalize_finish_reason(String.t() | atom() | nil) :: atom()
  def normalize_finish_reason(reason) when is_binary(reason) do
    reason
    |> String.downcase()
    |> String.to_atom()
    |> normalize_finish_reason()
  end

  def normalize_finish_reason(:stop), do: :stop
  def normalize_finish_reason(:end), do: :stop
  def normalize_finish_reason(:complete), do: :stop
  def normalize_finish_reason(:max_tokens), do: :length
  def normalize_finish_reason(:length), do: :length
  def normalize_finish_reason(:error), do: :error
  def normalize_finish_reason(nil), do: :stop
  def normalize_finish_reason(other) when is_atom(other), do: other

  @doc """
  Extracts content from various response formats.

  ## Examples

      iex> Altar.AI.Response.extract_content(%{text: "Hello"})
      "Hello"

      iex> Altar.AI.Response.extract_content(%{content: [%{text: "Hi"}]})
      "Hi"

  """
  @spec extract_content(map()) :: String.t()
  def extract_content(%{text: text}) when is_binary(text), do: text
  def extract_content(%{content: content}) when is_binary(content), do: content

  def extract_content(%{content: contents}) when is_list(contents) do
    contents
    |> Enum.map(fn
      %{text: text} when is_binary(text) -> text
      item when is_map(item) -> extract_content(item)
      _ -> ""
    end)
    |> Enum.join("")
  end

  def extract_content(%{message: %{content: content}}), do: extract_content(%{content: content})
  def extract_content(_), do: ""

  @doc """
  Merges metadata from provider response.

  Extracts provider-specific metadata while filtering out standard fields
  that are already normalized into the response structure.

  """
  @spec extract_metadata(map()) :: map()
  def extract_metadata(response) when is_map(response) do
    standard_fields = [:content, :text, :model, :tokens, :usage, :finish_reason, :stop_reason]

    response
    |> Map.drop(standard_fields)
    |> Map.drop(Enum.map(standard_fields, &Atom.to_string/1))
  end

  # Private helpers

  defp get_token_count(tokens, keys) do
    Enum.find_value(keys, 0, fn key ->
      Map.get(tokens, key) || Map.get(tokens, Atom.to_string(key))
    end)
  end
end
