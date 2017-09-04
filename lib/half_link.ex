defmodule HalfLink do
  def kill_them(pid) do
    us = self()

    HalfLink.start(us, pid)
  end

  def kill_us(pid) do
    us = self()

    HalfLink.start(pid, us)
  end

  use GenServer

  def start(watch, kill) do
    GenServer.start(__MODULE__, {watch, kill})
  end

  def init({watch, kill}) do
    Process.monitor(watch)
    Process.monitor(kill)
    {:ok, kill}
  end

  def handle_info({:DOWN, _ref, :process, kill, _reason}, kill) do
    {:stop, :normal, kill}
  end

  def handle_info({:DOWN, _ref, :process, _, reason}, kill) do
    Process.exit(kill, reason)
    {:stop, :normal, kill}
  end
end