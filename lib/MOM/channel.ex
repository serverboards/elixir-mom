require Logger

defmodule MOM.Channel do
  @moduledoc ~S"""
  A channel of communication. Subscribers are functions that will be
  called when somebody sends a message.

  There are several error conditions:

   * If a function raises an exception it is sent to the `:invalid` channel,
   * if there are no subscriber to the channel, it is sent to `:deadletter` channel
   * if the function raises an EXIT it will be removed from the functions to call

  There are several types of channels: named, broadcast and point to point.
  Named channels are broadcast channels with a name as an atom, as :invalid.

  ## Examples

```
  iex> require Logger
  iex> alias MOM.{Message, Channel}
  iex> {:ok, ch} = Channel.Broadcast.start_link
  iex> Channel.subscribe(ch, fn msg -> Logger.info("Message1 #{inspect msg}") end)
  iex> Channel.subscribe(ch, fn msg -> Logger.info("Message2  #{inspect msg}") end)
  iex> Channel.send(ch, %Message{ payload: %{method: "echo", param: "Hello world" }})
  :ok
  iex> Channel.unsubscribe(ch, 1)
  :ok

```

  It is allowed to call the channels after an atom

```
  iex> require Logger
  iex> alias MOM.{Message, Channel}
  iex> Channel.Named.start_link
  iex> id = Channel.subscribe(:deadletter, fn m -> Logger.error("Deadletter #{inspect m}") end)
  iex> Channel.send(:empty, %Message{}) # always returns ok
  iex> Channel.unsubscribe(:deadletter, id)
  :ok

```

  # Channel subscription

  In a broadcast channel the return value of the called function
  is discarded, but on other implementations may require `:ok`, `:nok` or `:empty`
  for further processing, so its good practive to return these values in your
  functions.

  Options:

  * `front:` (true|false) -- The subscriber is added at the front so it will be called first.
    Useful for tapping, for example. Default false.

  ## Examples

  A subscription normally calls a function when a message arrives

```
  iex> alias MOM.{Channel, Message}
  iex> require Logger
  iex> {:ok, ch} = Channel.Broadcast.start_link
  iex> Channel.subscribe(ch, fn _ ->
  ...>   Logger.info("Called")
  ...>   end)
  iex> Channel.send(ch, %MOM.Message{ id: 0 })
  :ok

```

  Its possible to subscribe to named channels

```
  iex> alias MOM.{Channel, Message}
  iex> Channel.subscribe(:named_channel, fn _ -> :ok end)
  iex> Channel.send(:named_channel, %Message{})
  :ok

```

  Its possible to subscribe a channel to a channel. This is useful to create
  tree like structures where some channels automatically write to another.

  All messages in orig are send automatically to dest.

```
  iex> require Logger
  iex> alias MOM.{Channel, Message}
  iex> {:ok, a} = Channel.Broadcast.start_link
  iex> {:ok, b} = Channel.Broadcast.start_link
  iex> Channel.subscribe(a, b)
  iex> Channel.subscribe(b, fn _ ->
  ...>    Logger.info("B called")
  ...>    end)
  iex> Channel.send(a, %MOM.Message{ id: 0, payload: "test"})
  :ok

```

  -- rework

  Uses ETS to keep the subscribers and a pointer to the dispatch method.

  Dispatch will get the channel, message and options.

  It should do the boracast, point to point or whatever.

  Named channels are intrinsic with a try / catch if named channel does not
  exist.
  """

  @doc ~S"""
  Subscribes to a channel.
  """
  def subscribe(channel, function, options \\ []) do
    GenServer.call(channel, {:subscribe, function, options})
  end
  @doc "Unsubscribes to a channel"
  def unsubscribe(channel, id) do
    GenServer.call(channel, {:unsubscribe, id})
  end

  def send(channel, message, options \\ [], timeout \\ 5_000) do
    {:ok, {mod, fun, args}} = GenServer.call(channel, {:get_dispatcher})
    apply(mod, fun, args ++ [message, options])
  end

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, %{}, options)
  end

  ## basic server impl
  def init(state) do
    table = :ets.new(:subscriptions, [])

    state = Map.merge(state, %{ maxid: 0, table: table})

    state = if not :dispatch in state do
      Map.put(state, :dispatch, {__MODULE__, :handle_dispatch, []})
    else state end

    {:ok, state}
  end

  def handle_call({:subscribe, func, options}, _from, state) do
    maxid = state.maxid
    subscriptions = :ets.insert(state.table, {maxid, {func, options}})

    state = %{ state
      | maxid: state.maxid + 1
    }

    {:reply, {:ok, maxid}, state}
  end

  def handle_call({:unsubscribe, id}, _from, state) do
    deleted = case :ets.lookup(state.table, id) do
      [{^id, _}] ->
        :ets.delete(state.table, id)
        true
      [] ->
        false
    end
    Logger.debug("Ndeleted #{inspect deleted}")

    {:reply, deleted, state}
  end

  def handle_call({:get_dispatcher}, _from, state) do
    {mod, fun, args} = state.dispatch
    {:reply, {:ok, {mod, fun, args ++ [state.table]}}, state}
  end


  def handle_dispatch(table, message, options) do
    # this code is called back at process caller of send
    :ets.foldl(fn {_, {func, opts}}, acc ->
      # Logger.debug("Call #{inspect {func, opts}} / #{inspect acc}")
      func.(message)
      acc + 1
    end, 0, table)
  end
end
