require Logger

defmodule MOM.RPC.EndPoint.JSON do
  use GenServer

  @doc ~S"""
  Connects an RPC to do JSON communications

  * `options` are the options:
    * `writef` : f(str) to write to the remote side
  """
  def start_link(endpoint, writef, options \\ []) do
    {:ok, pid} = GenServer.start_link(__MODULE__, endpoint, options)

    # On RPC, any message in just goes to the other side
    MOM.RPC.EndPoint.update_in(endpoint, fn
      %MOM.RPC.Request{method: method, params: params, reply: reply, id: id} ->
        GenServer.cast(pid, {:push_reply_to, id, reply})

        write_map(writef, %{
          id: id,
          method: method,
          params: params
        })

        :noreply

      other ->
        write_map(writef, other)
    end)

    {:ok, pid}
  end

  def stop(pid, reason \\ :normal) do
    GenServer.stop(pid, reason)
  end

  @doc ~S"""
  Parses a line from the client

  This is called from the user of this endpoint, not at MOM, for example from
  the WebSockets implementation.

  Returns:

  * :ok -- parsed and in processing
  * {:error, :bad_protocol} -- Invalid message, maybe not json, maybe not proper fields.
  """
  def parse_line(client, line, context \\ nil) do
    case line do
      '' ->
        :empty

      line ->
        res =
          case Poison.decode(line) do
            # these two are from the JSON side to the other side
            {:ok, %{"method" => method, "params" => params, "id" => id}} ->
              {in_, out} = GenServer.call(client, {:get_inout})

              MOM.Channel.send(out, %MOM.RPC.Request{
                method: method,
                params: params,
                id: id,
                context: context,
                reply: in_
              })

            {:ok, %{"method" => method, "params" => params}} ->
              {in_, out} = GenServer.call(client, {:get_inout})

              MOM.Channel.send(out, %MOM.RPC.Request{
                method: method,
                params: params,
                id: nil,
                context: context,
                reply: in_
              })

            # this are answers from JSON side to the other side
            {:ok, %{"result" => result, "id" => id}} ->
              out = GenServer.call(client, {:pop_reply_to, id})
              MOM.Channel.send(out, %MOM.RPC.Response{result: result, id: id})

            {:ok, %{"error" => error, "id" => id}} ->
              out = GenServer.call(client, {:pop_reply_to, id})
              MOM.Channel.send(out, %MOM.RPC.Response.Error{error: error, id: id})

            # no idea, should close.
            _ ->
              {:error, :bad_protocol}
          end

        if res == :stop do
          :ok
        else
          res
        end
    end
  end

  defp write_map({mod, fun, args}, map) do
    try do
      line =
        case Poison.encode(map) do
          {:ok, line} ->
            line

          {:error, e} ->
            Logger.error("Error encoding into JSON: #{inspect(e)}")

            case map do
              %MOM.RPC.Response{id: id} when not is_nil(id) ->
                {:ok, line} =
                  Poison.encode(%{
                    id: map.id,
                    error: "json_encoding"
                  })

                line

              %MOM.RPC.Response.Error{id: id} when not is_nil(id) ->
                {:ok, line} =
                  Poison.encode(%{
                    id: map.id,
                    error: "json_encoding"
                  })

                line

              _ ->
                false
            end
        end

      if line do
        args = args ++ [line]
        apply(mod, fun, args)
      end

      :ok
    rescue
      e in MatchError ->
        Logger.error("Can not convert message to JSON: #{inspect(e)}")
        :error
    end
  end

  ## Server impl

  def init(endpoint) do
    {:ok,
     %{
       in: endpoint.in,
       out: endpoint.out,
       reply_to: %{}
     }}
  end

  def handle_call({:get_inout}, _from, status) do
    {:reply, {status.in, status.out}, status}
  end

  def handle_call({:pop_reply_to, id}, _from, status) do
    {from, reply_to} = Map.pop(status.reply_to, id)
    status = %{status | reply_to: reply_to}

    {:reply, from, status}
  end

  def handle_cast({:push_reply_to, id, channel}, status) do
    {:noreply, %{status | reply_to: Map.put(status.reply_to, id, channel)}}
  end
end
