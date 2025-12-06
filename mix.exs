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
      aliases: aliases(),

      # Hex
      description:
        "Unified AI adapter foundation - protocols for gemini_ex, claude_agent_sdk, codex_sdk",
      package: package(),
      docs: docs(),

      # Testing
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # AI SDKs - ALL OPTIONAL (using path dependencies for local development)
      # Note: These are optional and may not compile - that's OK!
      # {:gemini, path: "../gemini_ex", optional: true},
      # {:claude_agent_sdk, path: "../claude_agent_sdk", optional: true},
      # {:codex_sdk, path: "../codex_sdk", optional: true},

      # Core
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},

      # Dev/Test
      # {:supertester, path: "../supertester", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      test: ["test --warnings-as-errors"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: @source_url
    ]
  end
end
