# Altar.AI

<p align="center">
  <img src="assets/altar_ai.svg" alt="Altar.AI Logo" width="200"/>
</p>

**Unified AI adapter foundation for Elixir** - Protocol-based abstractions for multiple AI providers

[![Hex.pm](https://img.shields.io/hexpm/v/altar_ai.svg)](https://hex.pm/packages/altar_ai)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/altar_ai)
[![License](https://img.shields.io/hexpm/l/altar_ai.svg)](https://github.com/nshkrdotcom/altar_ai/blob/main/LICENSE)

## Features

- **Protocol-Based Architecture** - Uses protocols instead of behaviours for maximum flexibility
- **Runtime Capability Detection** - Introspect what each adapter supports at runtime
- **Composite Adapters** - Automatic fallback chains across multiple providers
- **Framework Agnostic** - No dependencies on FlowStone, Synapse, or other frameworks
- **Unified Telemetry** - Standard telemetry events for monitoring and debugging
- **Comprehensive Testing** - Mock adapters and test utilities included

## Supported Providers

- **Gemini** - Google Gemini AI (via `gemini_ex`)
- **Claude** - Anthropic Claude (via `claude_agent_sdk`)
- **Codex** - OpenAI models (via `codex_sdk`)
- **Fallback** - Heuristic fallback (no external API required)
- **Mock** - Configurable mock for testing

All SDK dependencies are **optional** - Altar.AI works with whatever you have installed.

## Installation

Add `altar_ai` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:altar_ai, "~> 0.1.0"},
    # Optional: Add the AI SDKs you want to use
    # {:gemini, "~> 0.1.0"},
    # {:claude_agent_sdk, "~> 0.1.0"},
    # {:codex_sdk, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Basic Usage

```elixir
# Create an adapter
adapter = Altar.AI.Adapters.Gemini.new(api_key: "your-api-key")

# Generate text
{:ok, response} = Altar.AI.generate(adapter, "Explain Elixir protocols")
IO.puts(response.content)

# Check what the adapter can do
Altar.AI.capabilities(adapter)
#=> %{generate: true, stream: true, embed: true, batch_embed: true, ...}
```

### Composite Adapters with Fallbacks

```elixir
# Create a composite that tries multiple providers
composite = Altar.AI.Adapters.Composite.new([
  Altar.AI.Adapters.Gemini.new(),
  Altar.AI.Adapters.Claude.new(),
  Altar.AI.Adapters.Fallback.new()  # Always succeeds
])

# Or use the default chain (auto-detects available SDKs)
composite = Altar.AI.Adapters.Composite.default()

# Now generate with automatic fallback
{:ok, response} = Altar.AI.generate(composite, "Hello, world!")
```

### Embeddings

```elixir
adapter = Altar.AI.Adapters.Gemini.new()

# Single embedding
{:ok, vector} = Altar.AI.embed(adapter, "semantic search query")
length(vector)  #=> 768 (or model-specific dimension)

# Batch embeddings
{:ok, vectors} = Altar.AI.batch_embed(adapter, ["query 1", "query 2", "query 3"])
```

### Classification

```elixir
# Use fallback adapter for simple keyword-based classification
fallback = Altar.AI.Adapters.Fallback.new()

{:ok, classification} = Altar.AI.classify(
  fallback,
  "I love this product!",
  ["positive", "negative", "neutral"]
)

classification.label       #=> "positive"
classification.confidence  #=> 0.8
classification.all_scores  #=> %{"positive" => 0.8, "negative" => 0.2, "neutral" => 0.2}
```

### Code Generation

```elixir
adapter = Altar.AI.Adapters.Codex.new()

# Generate code
{:ok, code_result} = Altar.AI.generate_code(
  adapter,
  "Create a fibonacci function in Elixir",
  language: "elixir"
)

IO.puts(code_result.code)

# Explain code
{:ok, explanation} = Altar.AI.explain_code(
  adapter,
  "def fib(0), do: 0\ndef fib(1), do: 1\ndef fib(n), do: fib(n-1) + fib(n-2)"
)

IO.puts(explanation)
```

## Architecture

Altar.AI uses **protocols** instead of behaviours, providing several advantages:

1. **Runtime Dispatch** - Protocols dispatch on adapter structs, allowing cleaner composite implementations
2. **Capability Detection** - Easy runtime introspection of what each adapter supports
3. **Flexibility** - Adapters only implement the protocols they support

### Core Protocols

- `Altar.AI.Generator` - Text generation and streaming
- `Altar.AI.Embedder` - Vector embeddings
- `Altar.AI.Classifier` - Text classification
- `Altar.AI.CodeGenerator` - Code generation and explanation

### Capability Detection

```elixir
adapter = Altar.AI.Adapters.Gemini.new()

# Check specific capability
Altar.AI.supports?(adapter, :embed)  #=> true
Altar.AI.supports?(adapter, :classify)  #=> false

# Get all capabilities
Altar.AI.capabilities(adapter)
#=> %{
#=>   generate: true,
#=>   stream: true,
#=>   embed: true,
#=>   batch_embed: true,
#=>   classify: false,
#=>   generate_code: false,
#=>   explain_code: false
#=> }

# Human-readable description
Altar.AI.Capabilities.describe(adapter)
#=> "Gemini: text generation, streaming, embeddings, batch embeddings"
```

## Testing

Altar.AI provides a `Mock` adapter for testing:

```elixir
# Create a mock adapter
mock = Altar.AI.Adapters.Mock.new()

# Configure responses
mock = Altar.AI.Adapters.Mock.with_response(
  mock,
  :generate,
  {:ok, %Altar.AI.Response{content: "Test response", provider: :mock, model: "test"}}
)

# Use in tests
{:ok, response} = Altar.AI.generate(mock, "any prompt")
assert response.content == "Test response"

# Or use custom functions
mock = Altar.AI.Adapters.Mock.with_response(
  mock,
  :generate,
  fn prompt -> {:ok, %Altar.AI.Response{content: "Echo: #{prompt}"}} end
)
```

## Telemetry

All operations emit telemetry events under `[:altar, :ai]`:

```elixir
:telemetry.attach(
  "my-handler",
  [:altar, :ai, :generate, :stop],
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements, metadata})
  end,
  nil
)

# Events:
# [:altar, :ai, :generate, :start]
# [:altar, :ai, :generate, :stop]
# [:altar, :ai, :generate, :exception]
# [:altar, :ai, :embed, :start]
# [:altar, :ai, :embed, :stop]
# ... and more
```

## Hexagonal Architecture

Altar.AI follows the **Hexagonal (Ports & Adapters)** architecture:

- **Ports** - Protocols define the interface (`Generator`, `Embedder`, etc.)
- **Adapters** - Concrete implementations for each provider (`Gemini`, `Claude`, `Codex`)
- **Core** - Framework-agnostic types and logic

This makes it easy to:
- Swap providers without changing application code
- Add new providers by implementing protocols
- Test with mock adapters
- Build composite adapters with fallback chains

## License

MIT License - see [LICENSE](https://github.com/nshkrdotcom/altar_ai/blob/main/LICENSE) for details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- Inspired by the adapter pattern in Ecto and other Elixir libraries
- Built for use with [FlowStone](https://github.com/nshkrdotcom/flowstone) and [Synapse](https://github.com/nshkrdotcom/synapse)
