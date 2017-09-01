defmodule MyApp.AMQPConnection do
  use RabbitHutch.Connection

  def init(_) do
    {:ok, [
      username: "guest",
      password: "guest",
      host: "localhost"
    ]}
  end
end