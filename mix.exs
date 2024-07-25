defmodule Nominatim.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_nominatim,
      version: "1.1.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),

      # Docs
      name: "ExNominatim",
      source_url: "https://github.com/waseigo/ex_nominatim",
      homepage_url: "https://overbring.com/software/ex_nominatim",
      docs: [
        main: "readme",
        logo: "./etc/assets/ex_nominatim_logo.png",
        assets: "etc/assets",
        extras: ["README.md"]
      ]
    ]
  end

  defp description do
    """
    A full-featured client for the OpenStreetMap Nominatim API V1 (public and self-hosted), with extensive request validation, robust error-handling and reporting, and user guidance with helpful validation messages.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Isaak Tsalicoglou"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/waseigo/ex_nominatim"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31.0", only: :dev, runtime: false}
    ]
  end
end
