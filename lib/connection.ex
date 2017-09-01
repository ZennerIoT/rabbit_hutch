defmodule RabbitHutch.Connection do
  require Logger

  @type error :: 
    :no_connection |
    :timeout

  @channel_default_opts [
    timeout: nil,
    on_close: [:reopen]
  ]

  defmacro __using__(_) do
      quote do
      @behaviour RabbitHutch.Connection

      def start_link(opts \\ []) do
        RabbitHutch.Connection.start_link(__MODULE__, opts)
      end

      def channel(consumer, opts \\ []) do
        GenServer.call(__MODULE__, {:get_channel, consumer, opts})
      end
      
      def get_connection() do
        GenServer.call(__MODULE__, :get_connection)
      end
      
      defoverridable [start_link: 1, channel: 2]
    end
  end
  
  @callback start_link(opts :: []) :: {:ok, pid} | {:error, term}

  @doc """
  Initializes the connection, returning the connection options.

  ## Returned options

  * `:username` - The name of a user registered with the broker (defaults to “guest”);
  * `:password` - The password of user (defaults to “guest”);
  * `:virtual_host` - The name of a virtual host in the broker (defaults to “/“);
  * `:host` - The hostname of the broker (defaults to “localhost”);
  * `:port` - The port the broker is listening on (defaults to 5672);
  * `:channel_max` - The channel_max handshake parameter (defaults to 0);
  * `:frame_max` - The frame_max handshake parameter (defaults to 0);
  * `:heartbeat` - The hearbeat interval in seconds (defaults to 0 - turned off);
  * `:connection_timeout` - The connection timeout in milliseconds (defaults to infinity);
  * `:ssl_options` - Enable SSL by setting the location to cert files (defaults to none);
  * `:client_properties` - A list of extra client properties to be sent to the server, defaults to [];
  * `:socket_options` - Extra socket options. These are appended to the default options. See http://www.erlang.org/doc/man/inet.html#setopts-2 and http://www.erlang.org/doc/man/gen_tcp.html#connect-4 for descriptions of the available options.
  """
  @callback init(opts :: []) :: {:ok, opts :: []}

  @doc """
  Returns a channel for the given process. 

  The returned channel process will be monitored and 

  ## Options

   * `:timeout` - When not connected, give this much time in milliseconds to wait for a 
     reconnection, or return `{:error, :timeout}` 

     If `nil`, return `{:error, :no_connection}` when not able to open a channel process.
     
     **Default**: `#{inspect Keyword.get(@channel_default_opts, :timeout)}`
   * `:on_close` - When the channel closes, decides what should happen. 
     Pass a list of actions that are executed in the order that was passed.

    ** Default**: `#{inspect Keyword.get(@channel_default_opts, :on_close)}`

    Available actions:
     * `:info` - Sends `{:channel_closed, old_channel, reason}` to the given process
     * `:exit` - Exits the given process for the same reason the channel closed.
     * `:reopen` - Tries to re-open the channel immediately and returns it in the next call to `channel/2`.
    
  """
  @callback channel(pid, opts :: []) :: {:ok, pid} | {:error, error :: error}

  def start_link(module, opts \\ []) do
    GenServer.start_link(__MODULE__, {module, opts}, name: module)
  end

  defstruct [
    channels: nil, # the ets
    connection_opts: nil, 
    connection: nil,
    retry: 0,
    module: nil
  ]

  def init({module, opts}) do
    {:ok, opts} = module.init(opts)

    channel_table = :ets.new(:amqp_channels, [
      :ordered_set, 
      {:read_concurrency, true}, 
      {:write_concurrency, true}
    ])

    state = %__MODULE__{
      channels: channel_table, 
      connection_opts: opts,
      module: module
    }

    connect(state)
  end

  def connect(state) do
    result = with {:ok, connection} <- AMQP.Connection.open(state.connection_opts),
         _ref = Process.monitor(connection.pid),
      do: {:ok, %{state | connection: connection, retry: 0}}

    case result do
      {:ok, state} -> 
        {:ok, state}
      other ->
        {:error, other, Map.update(state, :retry, 0, &(&1 + 1))}
    end
  end

  defp next_retry(retry_num) do
    :erlang.floor(min(max(:math.pow(retry_num, 2) * 250, 100), 10_000))
  end

  def handle_call({:get_channel, consumer, opts}, _from, state) do
    opts = opts ++ @channel_default_opts
    
    case :ets.lookup(state.channels, consumer) do
      [{^consumer, record}] ->
        {:reply, {:ok, record.channel}, state}
      [] ->
        case AMQP.Channel.open(state.connection) do
          {:ok, channel} ->
            record = %__MODULE__.Record{
              channel: channel,
              consumer: consumer
            }
            :ets.insert(state.channels, {consumer, record})
            {:reply, {:ok, channel}, state}
          other ->
            {:reply, {:error, other}, state}
        end
    end
  end

  def handle_call(:get_connection, _from, %{connection: nil} = state) do
    {:reply, {:error, :no_connection}, state}
  end

  def handle_call(:get_connection, _from, %{connection: conn} = state) do
    {:reply, {:ok, conn}, state}
  end

  def handle_info(:"$reconnect", state) do
    Logger.info("#{inspect state.module} trying to reconnect")
    try_reconnect(state)
  end

  def handle_info({:DOWN, _ref, :process, connection_pid, reason}, %{connection: %{pid: connection_pid}} = state) do
    state = %{state | connection: nil}
    # TODO go through the list of channels, handle the actions
    Logger.error("#{inspect state.module} Connection to AMQP lost: #{inspect reason}")
    try_reconnect(state)
  end

  defp try_reconnect(state) do
    case connect(state) do
      {:ok, state} -> 
        #TODO reopen all the channels
        {:noreply, state}
      {:error, reason, state} ->
        timeout = next_retry(state.retry)

        Logger.warn("#{inspect state.module} Could not reconnect to AMQP Server, trying again in #{timeout} ms")

        Process.send_after self(), :"$reconnect", timeout
        {:noreply, state}
    end
  end
end