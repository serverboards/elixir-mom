require Logger

defmodule MOM.RPC.Endpoint.Caller do
  use GenServer

  def start_link(rpc_out, options \\ []) do
    {:ok, pid } = GenServer.start_link __MODULE__, rpc_out, options

    MOM.Channel.subscribe( rpc_out.reply, fn msg ->
      if msg.error do
        error(pid, msg.id, msg.error)
      else
        reply(pid, msg.id, msg.payload)
      end
    end)

    {:ok, %{ pid: pid, rpc_out: rpc_out }}
  end

  def stop(caller, reason) do
    GenServer.stop(caller.pid, reason)
  end

  def call(client, method, params, timeout \\ 60_000) do
    Logger.debug("Call!")
    GenServer.call(client.pid, {:call, method, params}, timeout)
  end

  def event(client, method, params) do
    MOM.Channel.send(client.rpc_out.request, %MOM.Message{ payload:
      %MOM.RPC.Message{ method: method, params: params}
      })
  end

  def reply(client, id, res) do
    GenServer.cast(client, {:reply, id, res})
  end
  def error(client, id, error) do
    GenServer.cast(client, {:error, id, error})
  end

  # server impl
  def init(rpc_out) do
    {:ok, %{
      rpc_out: rpc_out,
      maxid: 1,
      reply: %{}
    }}
  end

  def handle_call({:call, method, params}, from, status) do
    id = status.maxid
    pid = self()
    Task.start(fn ->
      ok = MOM.Channel.send(status.rpc_out.request, %MOM.Message{ payload:
        %MOM.RPC.Message{ method: method, params: params}, id: id
        } )
      case ok do
        :empty ->
          error(pid, id, :unknown_method)
        :nok ->
          error(pid, id, :unknown_method)
        :ok ->
          :ok # do nothing, wait for real reply
      end
    end)
    {:noreply, %{
      status |
      reply: Map.put(status.reply, id, from),
      maxid: status.maxid+1
      }
    }
  end

  def handle_cast({:reply, id, res}, status) do
    GenServer.reply( status.reply[id], {:ok, res} )

    {:noreply, %{ status |
      reply: Map.drop(status.reply, [id])
      }
    }
  end
  def handle_cast({:error, id, res}, status) do
    GenServer.reply( status.reply[id], {:error, res} )

    {:noreply, %{ status |
      reply: Map.drop(status.reply, [id])
      }
    }
  end
end
