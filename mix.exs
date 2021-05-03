defmodule RabbitHutch.Mixfile do
  use Mix.Project

  def project do
    [
      app: :rabbit_hutch,
      version: "1.0.0",
      elixir: "~> 1.4",
      start_permanent: Mix.env == :prod,
      deps: deps(),
      description: "Managed RabbitMQ channels with auto-reconnect and backoff",
      docs: [
        main: "RabbitHutch", # The main page in the docs
        extras: ["README.md"]
      ],
      package: package()
    ]
  end

  def package() do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/zenneriot/rabbit_hutch"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :amqp_client]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:amqp, "~> 0.3.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
