require Logger

defmodule MOM.Channel.PointToPoint do
  use MOM.Channel.Base

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

  alias MOM.{Message, Channel}

  @doc ~S"""
  Sends a message to the channel.

  Avaialble options are:
  * :all -- Sends to all channels, behaving as a broadcast channel.
  """
  def send(channel, %Message{} = message, options, timeout) do
    GenServer.call(channel.pid, {:send, message, options}, timeout)
  end

  ## Server impl

  @doc ~S"""
  Dispatchs a message to a list of subscribers.

  Returns a list of subscribers that must be removed as they have exitted.
  """
  def dispatch([], _msg), do: {:nok, []}
  def dispatch([ {id, f} | rest ], msg) do
    Logger.debug("Call to #{id}")
    ok = try do
      f.(msg)
    catch
      :exit, { cause, where} ->
        Logger.warn("Message #{inspect msg} to p2p channel into a exitted process. Removing listener. #{inspect cause}")
        Logger.debug(inspect where)
        :exit
    rescue
      e ->
        Channel.send(:invalid, %Message{ msg | error: {e, System.stacktrace()}} )
        Logger.error("Error sending #{inspect msg} to #{inspect f}. Sent to :invalid messages channel.\n#{inspect e}\n#{ Exception.format_stacktrace System.stacktrace }")
        :nok
    end

    Logger.debug("Call to #{id}: #{inspect ok}")

    case ok do
      :ok ->
        {:ok, []}
      :unsubscribe ->
        {ok, [{id, f}]}
      :exit -> # remove me, and any that later was said to be for removal
        {ok, toremove} = dispatch(rest, msg)
        {ok, [{id, f}] ++ toremove}
      :nok ->
        dispatch(rest, msg)
    end
  end

  @doc ~S"""
  Calls all subscribers in order until one returns :ok. If none returns :ok,
  returns :nok.

  Returns :empty if there are no subscribers.

  If no subscribers returns :empty
  """
  def handle_call({:send, msg, []}, _, state) do
    {ok, state} = if Enum.count(state.subscribers) == 0 do
      {:empty, state}
    else
      #Logger.debug("Dispatch to #{inspect state.subscribers}")
      {ok, toremove} = dispatch(state.subscribers, msg)
      subscribers = if toremove != [] do
        Enum.filter(state.subscribers, &(not &1 in toremove))
      else
        state.subscribers
      end

      if ok == :nok do
        Channel.send(:deadletter, %{ msg | error: :deadletter })
      end

      {ok, %{ state | subscribers: subscribers}}
    end
    #Logger.debug("End p2p #{inspect ok}")

    {:reply, ok, state}
  end

  def handle_call({:send, msg, options}, from, state) do
    if Enum.member? options, :all do
      MOM.Channel.Broadcast.handle_call({:send, msg, []}, from, state)
    else
      handle_call({:send, msg, []}, from, state)
    end
  end

  # ignore these messages, they come from creating a task for every call at MOM/method_caller.ex:309
  def handle_info({_ref, :ok}, state), do: {:noreply, state}
  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state), do: {:noreply, state}
  def handle_info(any, state) do
    Logger.warn("Received unexpected message: #{inspect any}")
    {:noreply, state}
  end
end
