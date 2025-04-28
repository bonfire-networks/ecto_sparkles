defmodule EctoSparkles.Project do
  use Mix.Project

  def project do
    [
      app: :ecto_sparkles,
      version: "0.2.1",
      description: "Helper library to better join + preload Ecto associations, and other goodies",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  defp package do
    [
      maintainers: ["Bonfire Networks"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/bonfire-networks/ecto_sparkles"},
      files: ~w(mix.exs README.md lib config)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: "https://github.com/bonfire-networks/ecto_sparkles"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application, do: [extra_applications: [:logger]]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.8"},
      {:ecto_sql, "~> 3.8"},
      {:ecto_dev_logger, "~> 0.9"},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:recase, "~> 0.8"},
      {:untangle, "~> 0.3"},
      {:json_serde, "~> 1.1", optional: true},
      {:html_sanitize_ex, "~> 1.4.3", optional: true}
    ]
  end
end
