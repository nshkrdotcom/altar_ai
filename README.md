# Altar.AI

[![Hex.pm](https://img.shields.io/hexpm/v/altar_ai.svg)](https://hex.pm/packages/altar_ai)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/altar_ai)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> Unified AI adapter foundation for Elixir - shared behaviours and adapters for gemini_ex, claude_agent_sdk, and codex_sdk

Altar.AI provides a consistent interface for working with multiple AI providers in Elixir. Write your code once and easily switch between Gemini, Claude, Codex, or any other AI provider.

## Features

- **Unified Behaviours** - Consistent interfaces for text generation, embeddings, classification, and code generation
- **Multiple Adapters** - Built-in support for Gemini, Claude, and Codex
- **Composite Fallbacks** - Chain multiple providers with automatic failover
- **Mock Testing** - Full testing support with configurable mock adapter
- **Telemetry Integration** - Built-in instrumentation for all operations
- **Heuristic Fallback** - Simple pattern-based responses when no AI is available
- **Type Safety** - Comprehensive typespecs for all public APIs

## Installation

Add `altar_ai` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:altar_ai, "~> 0.1.0"},
    # Add optional AI provider dependencies
    {:gemini, "~> 0.1.0"},
    {:claude_agent_sdk, "~> 0.1.0"},
    {:codex_sdk, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Basic Configuration

```elixir
# config/config.exs
config :altar_ai,
  default_adapter: Altar.AI.Adapters.Gemini,
  adapters: %{
    gemini: [
      api_key: {:system, "GEMINI_API_KEY"},
      model: "gemini-2.0-flash-exp"
    ]
  }
```

### Text Generation

```elixir
# Simple generation
{:ok, response} = Altar.AI.generate("What is Elixir?")
IO.puts(response.content)

# Streaming generation
{:ok, stream} = Altar.AI.stream("Tell me a story about dragons")
Enum.each(stream, fn chunk ->
  IO.write(chunk.content)
end)

# With options
{:ok, response} = Altar.AI.generate("Explain quantum computing",
  temperature: 0.7,
  max_tokens: 500
)
```

### Embeddings

```elixir
# Single embedding
{:ok, embedding} = Altar.AI.embed("semantic search query")
vector = embedding.vector  # [0.1, 0.2, 0.3, ...]

# Batch embeddings
{:ok, embeddings} = Altar.AI.batch_embed([
  "first query",
  "second query",
  "third query"
])
vectors = embeddings.vectors
```

### Classification

```elixir
{:ok, result} = Altar.AI.classify(
  "I absolutely love this product!",
  ["positive", "negative", "neutral"]
)

IO.puts("Label: #{result.label}")           # "positive"
IO.puts("Confidence: #{result.confidence}") # 0.95
IO.inspect(result.scores)                   # %{"positive" => 0.95, ...}
```

### Code Generation

```elixir
# Generate code
{:ok, code} = Altar.AI.generate_code(
  "Create a fibonacci function that handles edge cases",
  language: "elixir"
)
IO.puts(code.code)

# Explain code
{:ok, explanation} = Altar.AI.explain_code(
  "def fib(0), do: 0\ndef fib(1), do: 1\ndef fib(n), do: fib(n-1) + fib(n-2)",
  language: "elixir",
  detail_level: :detailed
)
IO.puts(explanation.explanation)
```

## Adapters

### Gemini

Wraps the `gemini` package for Google's Gemini API.

```elixir
config :altar_ai,
  adapters: %{
    gemini: [
      api_key: {:system, "GEMINI_API_KEY"},
      model: "gemini-2.0-flash-exp",
      embedding_model: "text-embedding-004"
    ]
  }

# Use directly
Altar.AI.Adapters.Gemini.generate("Hello")
Altar.AI.Adapters.Gemini.embed("search query")
```

**Implements:** TextGen, Embed

### Claude

Wraps the `claude_agent_sdk` package for Anthropic's Claude API.

```elixir
config :altar_ai,
  adapters: %{
    claude: [
      api_key: {:system, "ANTHROPIC_API_KEY"},
      model: "claude-3-opus-20240229"
    ]
  }

# Use directly
Altar.AI.Adapters.Claude.generate("Hello")
Altar.AI.Adapters.Claude.stream("Tell me a story")
```

**Implements:** TextGen

### Codex

Wraps the `codex_sdk` package for OpenAI's Codex/GPT API.

```elixir
config :altar_ai,
  adapters: %{
    codex: [
      api_key: {:system, "OPENAI_API_KEY"},
      model: "gpt-4"
    ]
  }

# Use directly
Altar.AI.Adapters.Codex.generate("Hello")
Altar.AI.Adapters.Codex.generate_code("create a sorting algorithm")
Altar.AI.Adapters.Codex.explain_code("def sort(list), do: Enum.sort(list)")
```

**Implements:** TextGen, CodeGen

### Composite

Chains multiple providers with automatic fallback and retry logic.

```elixir
config :altar_ai,
  default_adapter: Altar.AI.Adapters.Composite,
  adapters: %{
    composite: [
      providers: [
        {Altar.AI.Adapters.Gemini, []},
        {Altar.AI.Adapters.Claude, []},
        {Altar.AI.Adapters.Codex, []},
        {Altar.AI.Adapters.Fallback, []}
      ],
      fallback_on_error: true,
      max_retries: 3,
      retry_delay_ms: 1000,
      retry_on_types: [:rate_limit, :timeout, :network_error]
    ]
  }

# Automatically tries providers in order
{:ok, response} = Altar.AI.generate("Hello")
# Gemini tried first, falls back to Claude if it fails, etc.
```

**Implements:** TextGen, Embed, Classify, CodeGen

### Mock

Configurable mock adapter for testing.

```elixir
# In tests
config :altar_ai,
  default_adapter: Altar.AI.Adapters.Mock,
  adapters: %{
    mock: [
      responses: %{
        generate: {:ok, %{content: "Test response", ...}}
      },
      track_calls: true
    ]
  }

# Configure responses at runtime
Altar.AI.Adapters.Mock.set_response(:generate, {:ok, %{content: "Custom"}})

# Track calls
Altar.AI.generate("test")
calls = Altar.AI.Adapters.Mock.get_calls(:generate)

# Clear history
Altar.AI.Adapters.Mock.clear_calls()
Altar.AI.Adapters.Mock.reset()
```

**Implements:** TextGen, Embed, Classify, CodeGen

### Fallback

Heuristic-based adapter for basic responses without AI.

```elixir
config :altar_ai,
  adapters: %{
    fallback: [
      templates: %{
        greeting: "Hello! How can I help you today?",
        farewell: "Goodbye! Have a great day!"
      }
    ]
  }

# Recognizes basic patterns
{:ok, response} = Altar.AI.Adapters.Fallback.generate("hello")
# => "Hello! How can I help you today?"

# Simple sentiment classification
{:ok, result} = Altar.AI.Adapters.Fallback.classify(
  "I love this!",
  ["positive", "negative"]
)
# => %{label: "positive", confidence: 0.6, ...}
```

**Implements:** TextGen, Classify

## Behaviours

### TextGen

```elixir
defmodule MyAdapter do
  @behaviour Altar.AI.Behaviours.TextGen

  @impl true
  def generate(prompt, opts) do
    # Return normalized response
    {:ok, %{
      content: "Generated text",
      model: "my-model",
      tokens: %{prompt: 10, completion: 20, total: 30},
      finish_reason: :stop,
      metadata: %{}
    }}
  end

  @impl true
  def stream(prompt, opts) do
    stream = Stream.map(["chunk1", "chunk2"], fn chunk ->
      %{content: chunk, delta: true, finish_reason: nil}
    end)
    {:ok, stream}
  end
end
```

### Embed

```elixir
defmodule MyEmbedAdapter do
  @behaviour Altar.AI.Behaviours.Embed

  @impl true
  def embed(text, opts) do
    {:ok, %{
      vector: [0.1, 0.2, 0.3, ...],
      model: "embedding-model",
      dimensions: 768,
      metadata: %{}
    }}
  end

  @impl true
  def batch_embed(texts, opts) do
    {:ok, %{
      vectors: [[0.1, ...], [0.2, ...]],
      model: "embedding-model",
      dimensions: 768,
      metadata: %{}
    }}
  end
end
```

### Classify

```elixir
defmodule MyClassifier do
  @behaviour Altar.AI.Behaviours.Classify

  @impl true
  def classify(text, labels, opts) do
    {:ok, %{
      label: "positive",
      confidence: 0.95,
      scores: %{"positive" => 0.95, "negative" => 0.05},
      metadata: %{}
    }}
  end
end
```

### CodeGen

```elixir
defmodule MyCodeGen do
  @behaviour Altar.AI.Behaviours.CodeGen

  @impl true
  def generate_code(prompt, opts) do
    {:ok, %{
      code: "def hello, do: :world",
      language: "elixir",
      explanation: nil,
      model: "code-model",
      metadata: %{}
    }}
  end

  @impl true
  def explain_code(code, opts) do
    {:ok, %{
      explanation: "This defines a simple function...",
      language: "elixir",
      complexity: :simple,
      model: "code-model",
      metadata: %{}
    }}
  end
end
```

## Error Handling

All adapters return normalized errors:

```elixir
case Altar.AI.generate("Hello") do
  {:ok, response} ->
    IO.puts(response.content)

  {:error, %Altar.AI.Error{} = error} ->
    IO.puts("Error: #{error.type} - #{error.message}")
    IO.puts("Provider: #{error.provider}")
    IO.puts("Retryable? #{error.retryable?}")
    IO.inspect(error.details)
end
```

Error types: `:api_error`, `:validation_error`, `:rate_limit`, `:timeout`, `:network_error`, `:not_found`, `:permission_denied`

## Telemetry

Altar.AI emits telemetry events for all operations:

```elixir
:telemetry.attach(
  "my-handler",
  [:altar, :ai, :text_gen, :stop],
  fn event, measurements, metadata, _config ->
    IO.inspect(%{
      event: event,
      duration: measurements.duration,
      provider: metadata.provider,
      tokens: metadata.tokens
    })
  end,
  nil
)
```

Events:
- `[:altar, :ai, :text_gen, :start | :stop | :exception]`
- `[:altar, :ai, :embed, :start | :stop | :exception]`
- `[:altar, :ai, :classify, :start | :stop | :exception]`
- `[:altar, :ai, :code_gen, :start | :stop | :exception]`

## Testing

Use the Mock adapter in tests:

```elixir
defmodule MyAppTest do
  use ExUnit.Case

  setup do
    # Configure mock adapter
    Application.put_env(:altar_ai, :default_adapter, Altar.AI.Adapters.Mock)
    Altar.AI.Adapters.Mock.reset()

    on_exit(fn ->
      Application.delete_env(:altar_ai, :default_adapter)
    end)
  end

  test "my feature" do
    # Configure response
    Altar.AI.Adapters.Mock.set_response(:generate,
      {:ok, %{content: "Test response", model: "test", ...}}
    )

    # Test your code
    result = MyApp.do_something()
    assert result == expected

    # Verify calls
    calls = Altar.AI.Adapters.Mock.get_calls(:generate)
    assert length(calls) == 1
  end
end
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- [Hex Package](https://hex.pm/packages/altar_ai)
- [Documentation](https://hexdocs.pm/altar_ai)
- [GitHub](https://github.com/nshkrdotcom/altar_ai)
- [Changelog](CHANGELOG.md)

---

Built with Elixir and the power of unified AI interfaces.
