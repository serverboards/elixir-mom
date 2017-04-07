defmodule MOM.Mixfile do
  use Mix.Project

  def project do
    [app: :mom,
     version: "0.5.0",
     elixir: "~> 1.2",
     name: "Elixir MOM",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     description: description(),
     package: package(),
     docs: [
       logo: "docs/serverboards.png",
       extras: ["README.md"]
     ]
   ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      applications: [:logger],
      mod: {MOM, []}
    ]
  end

  defp description do
    """
    Message Oriented Middleware for Elixir
    """
  end

  defp package do
    [
      name: :mom,
      files: ["lib","test","mix.exs","README.md"],
      maintainers: ["David Moreno"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/serverboards/elixir-mom",
        "Serverboards" => "https://serverboards.io"
      }
    ]
  end

  defp deps do
    [
      {:poison, "~> 3.1"},
      {:uuid, "~> 1.1" },
      {:ex_doc, "~> 0.14", only: :dev},
      {:cmark, ">= 0.7.0", only: :dev},
    ]
  end
end
