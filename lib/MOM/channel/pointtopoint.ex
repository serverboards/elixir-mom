require Logger

defmodule MOM.Channel.PointToPoint do
  @moduledoc ~S"""
  Special channel on which only one competing consumer consume messages.

  Each consumer is called in order, and MUST return :ok or :nok
  if :nok, next in line will try. If none consumes its sent to
  :deadletter. If any consumer throws an exceptionis sent to :invalid messages.

  If sent to :deadletter or :invalid, returns :nok, else returns :ok. This eases
  composability.

  ## Example

  To use it, use normal Channel methods (send, subscribe, unsubscribe) on a
  PointToPoint.start_link.

```
  iex> require Logger
  iex> alias MOM.{Channel, Message, RPC}
  iex> {:ok, ch} = Channel.PointToPoint.start_link
  iex> Channel.subscribe(ch, fn msg ->
  ...>  case msg.payload do
  ...>    %RPC.Message{ method: "ping", params: [_] } ->
  ...>      Logger.info("Consumed ping message")
  ...>      :ok
  ...>    _ ->
  ...>      :nok
  ...>  end
  ...>end)
  iex> Channel.subscribe(ch, fn msg ->
  ...>  case msg.payload do
  ...>    %RPC.Message{ method: "pong", params: [_] } ->
  ...>      Logger.info("Consumed pong message")
  ...>      :ok
  ...>    _ ->
  ...>      :nok
  ...>  end
  ...>end)
  iex> Channel.send(ch, %Message{ id: 0, payload: %RPC.Message{ method: "ping", params: ["Hello"]}} )
  :ok
  iex> Channel.send(ch, %Message{ id: 0, payload: %RPC.Message{ method: "pong", params: ["Hello"]}} )
  :ok
  iex> Channel.send(ch, %Message{ id: 0, payload: %RPC.Message{ method: "other", params: ["Hello"]}} )
  :nok

```

  Channels can self-unsubscribe returning :unsubscribe from the
  called function.

  ```
  iex> alias MOM.{Channel, Message}
  iex> {:ok, a} = Channel.PointToPoint.start_link
  iex> {:ok, data} = Agent.start_link(fn -> 0 end)
  iex> Channel.subscribe(a, fn _ ->
  ...>   Logger.info("Called")
  ...>   Agent.update(data, &(&1 + 1))
  ...>  :unsubscribe
  ...> end)
  iex> Channel.send(a, %Message{})
  :unsubscribe
  iex> Channel.send(a, %Message{})
  :empty
  iex> :timer.sleep(100) #send is async, wait for it
  iex> Agent.get(data, &(&1))
  1

```

  """
  def start_link(options \\ nil) do
    options = if options == nil do
      []
    else
      [options]
    end
    MOM.Channel.start_link(dispatch: {__MODULE__, :handle_dispatch, options})
  end

  def handle_dispatch(ptp_options, table, message, options) do
    # this code is called back at process caller of send
    res = :ets.foldl(fn
      {_id, {func, _opts, _ref}}, :cont ->
        MOM.Channel.dispatch_one(func, message)
      _, :stop ->
        :stop
    end, :cont, table)

    # If not processed, and have a default behaviour, use it. Returns the proper :stop | :cont
    if res == :cont do
      case ptp_options[:default] do
        nil ->
          :cont
        default ->
          default.(message, options)
          :stop
      end
    else
      :stop
    end
  end
end
