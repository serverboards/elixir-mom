defmodule MOM.RPC.Client do
  @moduledoc ~S"""
  Standard layout for clients: JSON, Method caller and manual caller.

  It can be a TCP/Websocket client that need to be authenticated, or
  Command clients that are given authentication credentials at creation.

  """

  alias MOM.RPC.Endpoint
  alias MOM.RPC

  defstruct [
    left: nil,
    right: nil,
  ]
  @doc ~S"""
  Starts a communication with a client.

  Comunication is using JSON RPC.

  At initialization a function to write into the other end must be suplied, and
  new lines are added calling `parse_line`.

  ## Options

  * `name` -- Provides a name for this connection. For debug pourposes.
  * `writef`(line)  -- is a function that receives a line and writes it to the client.

  writef is a mandatory option

  """
  def start_link(options \\ []) do

    # Create new context, or reuse given one.
    context = case Keyword.get(options, :context, nil) do
      nil ->
        {:ok, context} = RPC.Context.start_link
        context
      context ->
        context
    end

    options = options ++ [context: context]
    options = if options[:writef] == :context do
      writef = &RPC.Context.set(context, :last_line, &1)
      [writef: writef] ++ options
    else
      options
    end

    {:ok, method_caller} = RPC.MethodCaller.start_link
    RPC.MethodCaller.add_method method_caller, "version", fn [] ->
      Mix.Project.config()[:version]
    end
    RPC.MethodCaller.add_method method_caller, "ping", fn [msg] -> msg end

    {:ok, rpc_a } = RPC.start_link name: :a
    {:ok, rpc_b } = RPC.start_link name: :b

    {:ok, json} = Endpoint.JSON.start_link(rpc_a, rpc_b, options)
    {:ok, method_caller} = Endpoint.MethodCaller.start_link(rpc_b, options ++ [method_caller: method_caller])
    {:ok, caller} = Endpoint.Caller.start_link(rpc_a, options)

    RPC.tap(rpc_a, "A")
    RPC.tap(rpc_b, "B")

    {:ok, %{
      left_in: json,
      left_out: json,
      right_in: method_caller,
      right_out: caller,
      context: context
    }}
  end

  def stop(client, reason \\ :normal) do
    Endpoint.JSON.stop(client.left_in, reason)
    Endpoint.MethodCaller.stop(client.right_in, reason)
    Endpoint.Caller.stop(client.right_out, reason)
    RPC.Context.stop(client.context, reason)
  end

  def parse_line(client, line) do
    Endpoint.JSON.parse_line(client.left_in, line)
  end

  def event_to_remote(client, method, param) do
    Endpoint.Caller.event(client.right_out, method, param)
  end

  def get(client, what, default \\ nil) do
    case what do
      :left -> client.left_in
      :left_in -> client.left_in
      :left_out -> client.left_out
      :right_in -> client.right_in
      :right_out -> client.right_out
      :context -> client.context
      other ->
        RPC.Context.get client.context, what, default
    end
  end

  def set(client, what, value) do
    RPC.Context.set client.context, what, value
  end
end
