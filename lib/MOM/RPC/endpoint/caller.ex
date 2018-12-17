require Logger

defmodule MOM.RPC.EndPoint.Caller do
  @moduledoc ~S"""
  A method caller to be able to call from code to other endpoints.

  This method caller can not receive requests. It avoids copy of messages,
  forcing in some cases two calls the the genserver (on call: getid and wait for
  id. This wait is answered actually by the emitter directly, with another extra
  indirection to get to who to answer).

  """
  use GenServer

  def new(options \\ []) do
    endpoint = MOM.RPC.EndPoint.new()

    {:ok, pid} = GenServer.start_link(__MODULE__, endpoint.out, options)

    MOM.RPC.EndPoint.update_in(endpoint, fn
      %MOM.RPC.Request{id: id} when not is_nil(id) ->
        MOM.Channel.send(endpoint.out, %{id: id, error: :unknown_method})
      %MOM.RPC.Request{} ->
        :ignore
      %MOM.RPC.Response{id: id, result: result} ->
        from = GenServer.call(pid, {:get_from, id})
        GenServer.reply(from, {:ok, result})
      %MOM.RPC.Response.Error{id: id, error: error} ->
        from = GenServer.call(pid, {:get_from, id})
        GenServer.reply(from, {:error, error})
      end, monitor: pid)

    {:ok, endpoint, pid}
  end

  def stop(caller, reason) do
    GenServer.stop(caller.pid, reason)
  end

  def call(client, method, params, timeout \\ 60_000) do
    {id, out} = GenServer.call(client, {:get_next_id_and_out})
    MOM.Channel.send(out, %MOM.RPC.Request{ id: id, method: method, params: params, context: nil})
    GenServer.call(client, {:wait_for, id}, timeout)
  end

  def event(client, method, params) do
    out = GenServer.call(client, {:get_out})
    MOM.Channel.send(out, %MOM.RPC.Request{
      id: nil, method: method, params: params, context: nil
    })
  end

  # server impl
  def init(out) do
    {:ok, %{
      out: out,
      maxid: 1,
      reply_to: %{}
    }}
  end

  def handle_call({:get_next_id_and_out}, _from, status) do
    {:reply, {status.maxid, status.out}, %{ status |
      maxid: status.maxid + 1,
    }}
  end
  def handle_call({:get_out}, _from, status) do
    {:reply, status.out, status}
  end

  def handle_call({:wait_for, id}, from, status) do
    {:noreply, %{ status |
      reply_to: Map.put(status.reply_to, id, from)
    }}
  end
  def handle_call({:get_from, id}, _from, status) do
    {from, reply_to} = Map.pop(status.reply_to, id)

    {:reply, from, %{ status |
      reply_to: reply_to
    }}
  end
end
