defmodule AgentToolPolicy.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/logandonley/agent_tool_policy"

  def project do
    [
      app: :agent_tool_policy,
      version: @version,
      elixir: "~> 1.15",
      name: "AgentToolPolicy",
      description:
        "AgentToolPolicy provides capability masks and autonomous-action policy for AI agent tool calls.",
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: [
        main: "readme",
        extras: ["README.md"],
        source_ref: "v#{@version}"
      ],
      dialyzer: [
        plt_core_path: "priv/plts/core.plt",
        plt_file: {:no_warn, "priv/plts/project.plt"}
      ],
      deps: deps()
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
