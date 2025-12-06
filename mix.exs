defmodule Altar.AI.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/altar_ai"

  def project do
    [
      app: :altar_ai,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Hex
      name: "AltarAI",
      description: description(),
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # AI SDKs - ALL OPTIONAL (compile-time detection)
      # {:gemini_ex, "~> 0.8", optional: true},
      # {:claude_agent_sdk, "~> 0.1", optional: true},
      # {:codex_sdk, "~> 0.1", optional: true},

      # Core
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},

      # Dev/Test
      {:mox, "~> 1.0", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp aliases do
    [
      test: ["test --warnings-as-errors"]
    ]
  end

  defp description do
    """
    Protocol-based AI adapter foundation for Elixir. Provides unified abstractions
    for gemini_ex, claude_agent_sdk, and codex_sdk with automatic fallback support,
    runtime capability detection, and built-in telemetry.
    """
  end

  defp package do
    [
      name: "altar_ai",
      maintainers: ["nshkrdotcom"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md assets),
      exclude_patterns: [
        "priv/plts",
        ".DS_Store"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "AltarAI",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      logo: "assets/altar_ai.svg",
      assets: %{"assets" => "assets"},
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Core API": [Altar.AI],
        Protocols: [
          Altar.AI.Generator,
          Altar.AI.Embedder,
          Altar.AI.Classifier,
          Altar.AI.CodeGenerator
        ],
        Adapters: [
          Altar.AI.Adapters.Gemini,
          Altar.AI.Adapters.Claude,
          Altar.AI.Adapters.Codex,
          Altar.AI.Adapters.Composite,
          Altar.AI.Adapters.Fallback,
          Altar.AI.Adapters.Mock
        ],
        Types: [
          Altar.AI.Response,
          Altar.AI.Error,
          Altar.AI.Classification,
          Altar.AI.CodeResult
        ],
        Utilities: [
          Altar.AI.Telemetry,
          Altar.AI.Capabilities
        ]
      ]
    ]
  end
end
