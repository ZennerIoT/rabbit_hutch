defmodule RabbitHutchTest do
  use ExUnit.Case
  doctest RabbitHutch

  @die :"No, I expect you to die!"

  test "can start and connect" do
    assert {:ok, pid} = MyApp.AMQPConnection.start_link()
    assert is_pid(pid)
  end

  test "can get a channel" do
    assert {:ok, _pid} = MyApp.AMQPConnection.start_link(), "Should start the connection"
    assert {:ok, channel} = MyApp.AMQPConnection.channel(self()), "Should get a channel from the connection"

    assert {:ok, ^channel} = MyApp.AMQPConnection.channel(self()), "Should reuse the existing channel"
  end

  test "will reconnect when connection crashes" do
    assert {:ok, _pid} = MyApp.AMQPConnection.start_link(), "Should start the connection"
    assert {:ok, conn} = MyApp.AMQPConnection.get_connection(), "Connection should be working"
    assert {:ok, chan1} = MyApp.AMQPConnection.channel(self()), "Should get a channel from the connection"

    Process.exit(conn.pid, @die)

    assert_receive {:connection_down, _reason}, 50, "Should receive a message telling us about the disconnect"
    
    assert_receive {:new_channel, chan2}, 50, "Should receive a new channel after reconnecting"

    assert chan1 != chan2, "New channel should not be the old one"


    assert {:ok, conn2} = MyApp.AMQPConnection.get_connection()

    assert conn.pid != conn2.pid
  end

  test "will message us about closed channels" do
    MyApp.AMQPConnection.start_link()
    {:ok, chan} = MyApp.AMQPConnection.channel(self())

    Process.exit(chan.pid, @die)

    assert_receive {:channel_down, ^chan, _reason}
  end

  test "will terminate connection if it dies" do
    {:ok, pid} = MyApp.AMQPConnection.start_link()
    Process.unlink(pid)

    {:ok, %{pid: conn}} = MyApp.AMQPConnection.get_connection()
    
    Process.exit(pid, @die)

    Process.sleep(50)

    assert not Process.alive?(conn)
  end
end
