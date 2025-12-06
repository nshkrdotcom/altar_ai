defmodule Altar.AI.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/altar_ai"

  def project do
    [
      app: :altar_ai,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Altar.AI.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Optional AI provider dependencies (uncomment when available)
      # {:gemini, "~> 0.1.0", optional: true},
      # {:claude_agent_sdk, "~> 0.1.0", optional: true},
      # {:codex_sdk, "~> 0.1.0", optional: true},

      # Core dependencies
      {:telemetry, "~> 1.2"},
      {:jason, "~> 1.4"},

      # Dev/Test dependencies
      {:mox, "~> 1.1", only: :test},
      {:stream_data, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp description do
    """
    Unified AI adapter foundation for Elixir. Provides shared behaviours and adapters
    for multiple AI providers including Gemini, Claude, and Codex. Features composable
    adapters, fallback chains, and comprehensive testing support.
    """
  end

  defp package do
    [
      name: "altar_ai",
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md assets),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["nshkrdotcom"]
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "Altar.AI",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        Behaviours: [
          Altar.AI.Behaviours.TextGen,
          Altar.AI.Behaviours.Embed,
          Altar.AI.Behaviours.Classify,
          Altar.AI.Behaviours.CodeGen
        ],
        Adapters: [
          Altar.AI.Adapters.Gemini,
          Altar.AI.Adapters.Claude,
          Altar.AI.Adapters.Codex,
          Altar.AI.Adapters.Composite,
          Altar.AI.Adapters.Mock,
          Altar.AI.Adapters.Fallback
        ],
        Utilities: [
          Altar.AI.Error,
          Altar.AI.Response,
          Altar.AI.Telemetry,
          Altar.AI.Config
        ]
      ]
    ]
  end
end
