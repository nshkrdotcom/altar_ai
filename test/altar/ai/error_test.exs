defmodule Altar.AI.ErrorTest do
  use ExUnit.Case, async: true

  alias Altar.AI.Error

  describe "new/4" do
    test "creates error with required fields" do
      error = Error.new(:rate_limit, "Too many requests", :gemini)

      assert error.type == :rate_limit
      assert error.message == "Too many requests"
      assert error.provider == :gemini
      assert error.details == %{}
      assert error.retryable? == true
    end

    test "creates error with custom retryable flag" do
      error = Error.new(:api_error, "Error", :claude, retryable?: false)

      assert error.retryable? == false
    end

    test "creates error with details" do
      details = %{status_code: 429, retry_after: 60}
      error = Error.new(:rate_limit, "Rate limited", :gemini, details: details)

      assert error.details == details
    end
  end

  describe "retryable_by_default?/1" do
    test "rate_limit errors are retryable" do
      assert Error.retryable_by_default?(:rate_limit)
    end

    test "timeout errors are retryable" do
      assert Error.retryable_by_default?(:timeout)
    end

    test "network_error errors are retryable" do
      assert Error.retryable_by_default?(:network_error)
    end

    test "validation errors are not retryable" do
      refute Error.retryable_by_default?(:validation_error)
    end

    test "api errors are not retryable by default" do
      refute Error.retryable_by_default?(:api_error)
    end
  end

  describe "to_string/1" do
    test "formats error as string" do
      error = Error.new(:timeout, "Request timed out", :claude)

      assert Error.to_string(error) == "[claude] timeout: Request timed out"
    end
  end

  describe "String.Chars protocol" do
    test "implements to_string" do
      error = Error.new(:api_error, "API failed", :gemini)

      assert to_string(error) == "[gemini] api_error: API failed"
    end
  end
end
