defmodule Altar.AI.Adapters.CompositeTest do
  use ExUnit.Case, async: false

  alias Altar.AI.Adapters.{Composite, Mock}
  alias Altar.AI.Error

  setup do
    # Reset mock adapter before each test
    Mock.reset()

    # Configure composite to use mock adapter
    Application.put_env(:altar_ai, :adapters, %{
      composite: [
        providers: [{Mock, []}],
        max_retries: 2,
        retry_delay_ms: 10,
        retry_on_types: [:rate_limit, :timeout]
      ]
    })

    on_exit(fn ->
      Application.delete_env(:altar_ai, :adapters)
    end)

    :ok
  end

  describe "generate/2" do
    test "returns response from first successful provider" do
      {:ok, response} = Composite.generate("Hello")

      assert response.content =~ "mocked"
      assert response.metadata.provider == :mock
    end

    test "falls back to next provider on error" do
      # Configure composite with a failing provider then Mock
      defmodule FailingProvider do
        @behaviour Altar.AI.Behaviours.TextGen

        def generate(_prompt, _opts) do
          {:error, Error.new(:api_error, "Failed", :failing)}
        end

        def stream(_prompt, _opts) do
          {:error, Error.new(:api_error, "Failed", :failing)}
        end
      end

      Application.put_env(:altar_ai, :adapters, %{
        composite: [
          providers: [{FailingProvider, []}, {Mock, []}],
          max_retries: 1
        ]
      })

      {:ok, response} = Composite.generate("Hello")

      # Should succeed with Mock adapter
      assert response.content =~ "mocked"
      assert response.metadata.provider == :mock
    end

    test "returns error when all providers fail" do
      defmodule AllFailProvider do
        @behaviour Altar.AI.Behaviours.TextGen

        def generate(_prompt, _opts) do
          {:error, Error.new(:api_error, "Always fails", :failing)}
        end

        def stream(_prompt, _opts) do
          {:error, Error.new(:api_error, "Always fails", :failing)}
        end
      end

      Application.put_env(:altar_ai, :adapters, %{
        composite: [
          providers: [{AllFailProvider, []}],
          max_retries: 1
        ]
      })

      {:error, error} = Composite.generate("Hello")

      assert error.type == :api_error
      assert error.message == "All providers failed"
      assert error.provider == :composite
      assert is_list(error.details.errors)
      assert length(error.details.errors) == 1
    end

    test "retries on retryable errors" do
      # Create a provider that fails once then succeeds
      defmodule RetryableProvider do
        use Agent

        def start_link(_) do
          Agent.start_link(fn -> 0 end, name: __MODULE__)
        end

        @behaviour Altar.AI.Behaviours.TextGen

        def generate(_prompt, _opts) do
          count = Agent.get_and_update(__MODULE__, fn c -> {c, c + 1} end)

          if count == 0 do
            {:error, Error.new(:rate_limit, "Rate limited", :retryable, retryable?: true)}
          else
            {:ok,
             %{
               content: "Success after retry",
               model: "test",
               tokens: %{prompt: 1, completion: 1, total: 2},
               finish_reason: :stop,
               metadata: %{}
             }}
          end
        end

        def stream(_prompt, _opts), do: generate("", [])
      end

      {:ok, _} = start_supervised(RetryableProvider)

      Application.put_env(:altar_ai, :adapters, %{
        composite: [
          providers: [{RetryableProvider, []}],
          max_retries: 3,
          retry_delay_ms: 10,
          retry_on_types: [:rate_limit]
        ]
      })

      {:ok, response} = Composite.generate("Hello")

      assert response.content == "Success after retry"
    end
  end

  describe "embed/2" do
    test "delegates to configured provider" do
      {:ok, response} = Composite.embed("test text")

      assert is_list(response.vector)
      assert response.metadata.provider == :mock
    end
  end

  describe "classify/3" do
    test "delegates to configured provider" do
      {:ok, result} = Composite.classify("test", ["a", "b"])

      assert result.label in ["a", "b"]
      assert result.metadata.provider == :mock
    end
  end

  describe "generate_code/2" do
    test "delegates to configured provider" do
      {:ok, response} = Composite.generate_code("create function")

      assert is_binary(response.code)
      assert response.metadata.provider == :mock
    end
  end

  describe "explain_code/2" do
    test "delegates to configured provider" do
      {:ok, response} = Composite.explain_code("def hello, do: :world")

      assert is_binary(response.explanation)
      assert response.metadata.provider == :mock
    end
  end
end
