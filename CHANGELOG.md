# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-01-XX

### Added

- Initial release of Altar.AI
- Core behaviours:
  - `Altar.AI.Behaviours.TextGen` - Text generation interface
  - `Altar.AI.Behaviours.Embed` - Embedding generation interface
  - `Altar.AI.Behaviours.Classify` - Text classification interface
  - `Altar.AI.Behaviours.CodeGen` - Code generation and explanation interface
- Adapters:
  - `Altar.AI.Adapters.Gemini` - Google Gemini API adapter
  - `Altar.AI.Adapters.Claude` - Anthropic Claude API adapter
  - `Altar.AI.Adapters.Codex` - OpenAI Codex/GPT API adapter
  - `Altar.AI.Adapters.Composite` - Multi-provider fallback chain
  - `Altar.AI.Adapters.Mock` - Testing and development mock adapter
  - `Altar.AI.Adapters.Fallback` - Heuristic-based fallback adapter
- Utilities:
  - `Altar.AI.Error` - Unified error handling
  - `Altar.AI.Response` - Response normalization helpers
  - `Altar.AI.Telemetry` - Built-in telemetry instrumentation
  - `Altar.AI.Config` - Configuration management
- Main API:
  - `Altar.AI.generate/2` - Text generation
  - `Altar.AI.stream/2` - Streaming text generation
  - `Altar.AI.embed/2` - Embedding generation
  - `Altar.AI.batch_embed/2` - Batch embedding generation
  - `Altar.AI.classify/3` - Text classification
  - `Altar.AI.generate_code/2` - Code generation
  - `Altar.AI.explain_code/2` - Code explanation
- Comprehensive test suite
- Full documentation with examples

### Features

- Unified interface for multiple AI providers
- Automatic response normalization across providers
- Composite adapter with retry logic and automatic fallback
- Telemetry events for monitoring and debugging
- Mock adapter with call tracking for testing
- Type-safe API with comprehensive typespecs
- Configuration via application environment
- Support for environment variable interpolation
- Heuristic fallback for basic functionality without AI

[0.1.0]: https://github.com/nshkrdotcom/altar_ai/releases/tag/v0.1.0
