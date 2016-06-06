require Logger

defmodule MOM.RPC do
  @moduledoc ~S"""
  Gateway adapter for RPC.

  Creates a command and a response channel, which has to be connected to a RPC
  processor.

  It also has Method Caller lists to call directly and can be chained

  Options:

   * `context` -- Use the given context, if none, creates one
   * `method_caller: [mc|nil|false]` -- Use the given method caller, if nil create one, false dont use.

  `method_caller: false` is needed when connecting with an endpoint that provides all
  method calling, for example a remote side.

  ## Example of use

  It can be used in a blocking fasion

```
  iex> alias MOM.{Message, Channel, RPC}
  iex> {:ok, rpc} = RPC.start_link
  iex> {:ok, caller} = RPC.Endpoint.Caller.start_link(rpc)
  iex> Channel.subscribe(rpc.request, fn msg ->
  ...>  Channel.send(rpc.reply, %Message{ payload: msg.payload.params, id: msg.id })
  ...>   :ok
  ...>   end, front: true) # dirty echo rpc.
  iex> RPC.Endpoint.Caller.call(caller, "echo", "Hello world!")
  {:ok, "Hello world!"}

```

  Or non blocking

```
  iex> alias MOM.{Message, Channel, RPC}
  iex> require Logger
  iex> {:ok, rpc} = RPC.start_link
  iex> {:ok, caller} = RPC.Endpoint.Caller.start_link(rpc)
  iex> Channel.subscribe(rpc.request, fn msg -> Channel.send(msg.reply_to, %Message{ payload: msg.payload.params, id: msg.id }) end) # dirty echo rpc.
  iex> RPC.Endpoint.Caller.cast(caller, "echo", "Hello world!", fn answer -> Logger.info("Got the answer: #{answer}") end)
  :ok

```

  Returns `{:error, :unkown_method}` when method does not exist

```
  iex> alias MOM.RPC
  iex> {:ok, rpc} = RPC.start_link
  iex> {:ok, caller} = RPC.Endpoint.Caller.start_link(rpc)
  iex> RPC.Endpoint.Caller.call(caller, "echo", "Hello world!")
  {:error, :unknown_method}

```

  dir is a method caller functionality, so no method caller, no dir.

```
  iex> alias MOM.RPC
  iex> {:ok, rpc} = RPC.start_link method_caller: false
  iex> {:ok, caller} = RPC.Endpoint.Caller.start_link(rpc)
  iex> RPC.Endpoint.Caller.call(caller, "dir", [])
  {:error, :unknown_method}

```
  """
  defstruct [
    request: nil, # gets inside the MOM,
    reply: nil, # gets out of the MOM.
  ]

  alias MOM.Channel

  def start_link(options \\ []) do
    {:ok, request} = Channel.PointToPoint.start_link
    {:ok, reply} = Channel.PointToPoint.start_link
    {:ok, %MOM.RPC{ request: request, reply: reply } }
  end

  @doc ~S"""
  Stops the server
  """
  def stop(rpc) do
    MOM.Channel.stop(rpc.request)
    MOM.Channel.stop(rpc.reply)
  end

  @doc ~S"""
  Taps into the channels
  """
  def tap(rpc, name \\ nil) do
    name = if name do
      name
    else
      String.slice (inspect rpc.reply.pid), 5..-2
    end
    MOM.Tap.tap(rpc.request, name <> "_request")
    MOM.Tap.tap(rpc.reply, name <> "_reply")
  end

  @doc ~S"""
  Joins two RPC channels, to create networks.

  From left to right, any request on the right side may be done on the
  right side (if nobody replied it before). Replies from right to left.
  """
  def chain(left, right) do
    MOM.Channel.subscribe(left.request, right.request)
    MOM.Channel.subscribe(right.reply, left.reply)
  end
end
