defmodule Altar.AI.Error do
  @moduledoc """
  Unified error structure for all Altar.AI operations.

  This module provides a consistent error format across all AI providers,
  making it easier to handle errors uniformly regardless of the underlying
  provider implementation.

  ## Fields

    * `:type` - The category of error (`:api_error`, `:validation_error`,
      `:rate_limit`, `:timeout`, `:network_error`, `:not_found`, `:permission_denied`)
    * `:message` - Human-readable error message
    * `:provider` - The AI provider that generated the error (`:gemini`, `:claude`,
      `:codex`, etc.)
    * `:details` - Provider-specific error details (map)
    * `:retryable?` - Whether the operation can be safely retried

  ## Examples

      iex> error = %Altar.AI.Error{
      ...>   type: :rate_limit,
      ...>   message: "Rate limit exceeded",
      ...>   provider: :gemini,
      ...>   retryable?: true
      ...> }
      iex> error.retryable?
      true

  """

  @type error_type ::
          :api_error
          | :validation_error
          | :rate_limit
          | :timeout
          | :network_error
          | :not_found
          | :permission_denied
          | :unknown

  @type provider :: :gemini | :claude | :codex | :composite | :mock | :fallback | atom()

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          provider: provider(),
          details: map(),
          retryable?: boolean()
        }

  @enforce_keys [:type, :message, :provider]
  defstruct [
    :type,
    :message,
    :provider,
    details: %{},
    retryable?: false
  ]

  @doc """
  Creates a new error struct.

  ## Examples

      iex> Altar.AI.Error.new(:rate_limit, "Too many requests", :gemini, retryable?: true)
      %Altar.AI.Error{
        type: :rate_limit,
        message: "Too many requests",
        provider: :gemini,
        retryable?: true
      }

  """
  @spec new(error_type(), String.t(), provider(), keyword()) :: t()
  def new(type, message, provider, opts \\ []) do
    %__MODULE__{
      type: type,
      message: message,
      provider: provider,
      details: Keyword.get(opts, :details, %{}),
      retryable?: Keyword.get(opts, :retryable?, retryable_by_default?(type))
    }
  end

  @doc """
  Determines if an error type is typically retryable.

  ## Examples

      iex> Altar.AI.Error.retryable_by_default?(:rate_limit)
      true

      iex> Altar.AI.Error.retryable_by_default?(:validation_error)
      false

  """
  @spec retryable_by_default?(error_type()) :: boolean()
  def retryable_by_default?(type) do
    type in [:rate_limit, :timeout, :network_error]
  end

  @doc """
  Converts an error to a human-readable string.

  ## Examples

      iex> error = Altar.AI.Error.new(:timeout, "Request timed out", :claude)
      iex> Altar.AI.Error.to_string(error)
      "[claude] timeout: Request timed out"

  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = error) do
    "[#{error.provider}] #{error.type}: #{error.message}"
  end

  defimpl String.Chars do
    def to_string(error), do: Altar.AI.Error.to_string(error)
  end
end
