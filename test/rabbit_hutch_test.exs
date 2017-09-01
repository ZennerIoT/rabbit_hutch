defmodule RabbitHutchTest do
  use ExUnit.Case
  doctest RabbitHutch

  test "can start and connect" do
    assert {:ok, pid} = MyApp.AMQPConnection.start_link()
    assert is_pid(pid)
  end

  test "can get a channel" do
    assert {:ok, _pid} = MyApp.AMQPConnection.start_link()
    assert {:ok, channel} = MyApp.AMQPConnection.channel(self())

    # test if the existing channel is reused
    assert {:ok, ^channel} = MyApp.AMQPConnection.channel(self())
  end

  test "will reconnect when connection crashes" do
    assert {:ok, _pid} = MyApp.AMQPConnection.start_link()
    assert {:ok, conn} = MyApp.AMQPConnection.get_connection()

    Process.exit(conn.pid, :normal)

    Process.sleep(10)

    assert {:ok, conn2} = MyApp.AMQPConnection.get_connection()

    assert conn.pid != conn2.pid
  end
end
