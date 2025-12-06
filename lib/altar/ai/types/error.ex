defmodule Altar.AI.Error do
  @moduledoc """
  Unified error type across all AI providers.

  Normalizes errors from different providers into a consistent structure,
  making error handling uniform across the application.
  """

  defexception [:type, :message, :provider, :details, :retryable?]

  @type error_type ::
          :rate_limit
          | :auth
          | :invalid_request
          | :server_error
          | :timeout
          | :unavailable
          | :unsupported
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          provider: atom(),
          details: map(),
          retryable?: boolean()
        }

  @doc """
  Get the error message for display.
  """
  def message(%__MODULE__{message: msg}), do: msg

  @doc """
  Create a new error.

  ## Examples

      iex> Altar.AI.Error.new(:rate_limit, "Too many requests")
      %Altar.AI.Error{type: :rate_limit, message: "Too many requests", retryable?: true}
  """
  def new(type, message, opts \\ []) do
    %__MODULE__{
      type: type,
      message: message,
      provider: Keyword.get(opts, :provider),
      details: Keyword.get(opts, :details, %{}),
      retryable?: Keyword.get(opts, :retryable?, retryable_by_default?(type))
    }
  end

  @doc """
  Convert a Gemini error to a normalized error.
  """
  def from_gemini_error(error) do
    case error do
      %{status: 429} ->
        new(:rate_limit, "Gemini rate limit exceeded", provider: :gemini, retryable?: true)

      %{status: 401} ->
        new(:auth, "Gemini authentication failed", provider: :gemini, retryable?: false)

      %{status: 400} ->
        new(:invalid_request, "Invalid request to Gemini",
          provider: :gemini,
          retryable?: false
        )

      %{status: status} when status >= 500 ->
        new(:server_error, "Gemini server error", provider: :gemini, retryable?: true)

      {:error, :timeout} ->
        new(:timeout, "Gemini request timeout", provider: :gemini, retryable?: true)

      _ ->
        new(:unknown, "Unknown Gemini error: #{inspect(error)}",
          provider: :gemini,
          details: %{original: error}
        )
    end
  end

  @doc """
  Convert a Claude error to a normalized error.
  """
  def from_claude_error(error) do
    case error do
      %{type: "rate_limit_error"} ->
        new(:rate_limit, "Claude rate limit exceeded", provider: :claude, retryable?: true)

      %{type: "authentication_error"} ->
        new(:auth, "Claude authentication failed", provider: :claude, retryable?: false)

      %{type: "invalid_request_error"} ->
        new(:invalid_request, "Invalid request to Claude",
          provider: :claude,
          retryable?: false
        )

      _ ->
        new(:unknown, "Unknown Claude error: #{inspect(error)}",
          provider: :claude,
          details: %{original: error}
        )
    end
  end

  @doc """
  Convert a Codex/OpenAI error to a normalized error.
  """
  def from_codex_error(error) do
    case error do
      %{error: %{code: "rate_limit_exceeded"}} ->
        new(:rate_limit, "OpenAI rate limit exceeded", provider: :codex, retryable?: true)

      %{error: %{code: "invalid_api_key"}} ->
        new(:auth, "OpenAI authentication failed", provider: :codex, retryable?: false)

      %{error: %{code: "invalid_request_error"}} ->
        new(:invalid_request, "Invalid request to OpenAI",
          provider: :codex,
          retryable?: false
        )

      {:error, :timeout} ->
        new(:timeout, "OpenAI request timeout", provider: :codex, retryable?: true)

      _ ->
        new(:unknown, "Unknown OpenAI error: #{inspect(error)}",
          provider: :codex,
          details: %{original: error}
        )
    end
  end

  # Determine if an error type is retryable by default
  defp retryable_by_default?(type) do
    type in [:rate_limit, :server_error, :timeout, :unavailable]
  end
end
