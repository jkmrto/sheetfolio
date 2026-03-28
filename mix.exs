defmodule Sheetfolio.MixProject do
  use Mix.Project

  def project do
    [
      app: :sheetfolio,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Sheetfolio.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:goth, "~> 1.4"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:bandit, "~> 1.5"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev}
    ]
  end

  defp aliases do
    [
      "assets.build": ["esbuild default"],
      "assets.deploy": ["esbuild default --minify"]
    ]
  end
end
