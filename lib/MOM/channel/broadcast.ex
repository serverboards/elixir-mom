require Logger

defmodule MOM.Channel.Broadcast do
  @moduledoc ~S"""
  Broadcast channel. All messages are sent to all clients.
  """

  @doc ~S"""
  Send a message to a channel.

  Always returns :ok and it is asynchronous.

  The way to know if it was sucesfull is listen to the :invalid channel.

  ## Options

  * sync -- Default false. Wait untill all messages processed.

  ## Examples

  Depending on how succesful was the `send` it returns different values:

```
  iex> alias MOM.{Channel, Message}
  iex> {:ok, ch} = Channel.Broadcast.start_link
  iex> Channel.send(ch, %Message{})
  :ok
  iex> Channel.subscribe(ch, fn _ -> :ok end)
  iex> Channel.send(ch, %Message{})
  :ok
  iex> Channel.subscribe(ch, fn _ -> raise "To return :nok" end)
  iex> Channel.send(ch, %Message{}, sync: true)
  :ok

```

  Channels can self-unsubscribe returning :unsubscribe from the
  called function.

  ```
  iex> alias MOM.{Channel, Message}
  iex> {:ok, a} = Channel.Broadcast.start_link
  iex> {:ok, data} = Agent.start_link(fn -> 0 end)
  iex> Channel.subscribe(a, fn _ ->
  ...>   Logger.info("Called")
  ...>   Agent.update(data, &(&1 + 1))
  ...>  :unsubscribe
  ...> end)
  iex> Channel.send(a, %Message{})
  :ok
  iex> Channel.send(a, %Message{})
  :ok
  iex> :timer.sleep(100) #send is async, wait for it
  iex> Agent.get(data, &(&1))
  1

```
  """

  def start_link(options \\ []) do
    MOM.Channel.start_link(dispatch: {__MODULE__, :handle_dispatch, options})
  end

  def handle_dispatch(table, message, options) do
    Task.async(fn ->
      MOM.Channel.handle_dispatch(table, message, options)
    end)
  end
end
