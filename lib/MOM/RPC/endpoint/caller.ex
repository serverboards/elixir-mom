require Logger

defmodule MOM.RPC.Endpoint.Caller do
  use GenServer

  def start_link(rpc_out, options \\ []) do
    {:ok, pid } = GenServer.start_link __MODULE__, rpc_out, options

    MOM.Channel.subscribe( rpc_out.reply, fn msg ->
      GenServer.cast(pid, {:reply, msg})
    end)

    {:ok, %{ pid: pid, rpc_out: rpc_out }}
  end

  def stop(caller, reason) do
    GenServer.stop(caller.pid, reason)
  end


  def call(client, method, params) do
    GenServer.call(client.pid, {:call, method, params})
  end

  def cast(client, method, params, cb) do
    GenServer.cast(client.pid, {:cast, method, params, cb})
  end

  def event(client, method, params) do
    MOM.Channel.send(client.rpc_out.request, %MOM.Message{ payload:
      %MOM.RPC.Message{ method: method, params: params}
      })
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
    ok = MOM.Channel.send(status.rpc_out.request, %MOM.Message{ payload:
      %MOM.RPC.Message{ method: method, params: params}, id: id
      } )
    Logger.debug("Return from cast: #{inspect ok}")
    case ok do
      :empty ->
        {:reply, {:error, :unknown_method}, status}
      :nok ->
        {:reply, {:error, :unknown_method}, status}
      :ok ->
        {:noreply, %{
          status |
          reply: Map.put(status.reply, id, from),
          maxid: status.maxid+1
          }
        }
    end
  end

  def handle_cast({:reply, msg}, status) do
    result = if msg.error do
      {:error, msg.error}
    else
      {:ok, msg.payload}
    end
    case status.reply[msg.id] do
      f when is_function(f) -> # used at cast
        require Logger
        Logger.info("Call result #{inspect f} #{inspect result}")
        f.( result )
      {pid, _} = from when is_pid(pid) -> # used at call
        GenServer.reply( from, result )
    end

    {:noreply, %{ status |
      reply: Map.drop(status.reply, [msg.id])
      }
    }
  end

  def handle_cast({:cast, method, params, cb}, status) when is_function(cb) do
    id = status.maxid
    ok = MOM.Channel.send(status.rpc_out.request, %MOM.Message{ payload:
      %MOM.RPC.Message{ method: method, params: params}, id: id
      } )
    case ok do
      :nok -> # Could not send it
        cb.({:error, :unknown_method})
        {:noreply, status}
      :ok ->
        {:noreply, %{ status |
          reply: Map.put(status.reply, id, cb),
          maxid: status.maxid+1
        }
      }
    end

  end
end
