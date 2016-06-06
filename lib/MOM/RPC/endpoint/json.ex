require Logger

defmodule MOM.RPC.Endpoint.JSON do
  alias MOM.Channel


  @doc ~S"""
  Connects an RPC to do JSON communications

  * `rpc_in` is the RPC channel that will receive calls and events
  * `rpc_out` is the RPC channel on which this endpoint will perform the
    calls and receive the responses.
  * `options` are the options:
    * `writef` : f(str) to write to the remote side
  """
  def start_link(rpc_in, rpc_out, options \\ []) do
    client = %{
      writef: options[:writef],
      rpc_in: rpc_in,
      rpc_out: rpc_out
    }

    # I will receive requests here
    Channel.subscribe(rpc_in.request, fn msg ->
      call_in( client, msg.payload.method, msg.payload.params, msg.id )
    end)

    # and replies here
    Channel.subscribe(rpc_out.reply, fn msg ->
      if msg.error do
        error_out( client, msg.error, msg.id )
      else
        reply_out( client, msg.payload, msg.id )
      end
    end)

    {:ok, client}
  end

  def stop(json, reason) do
    :ok
  end

  @doc ~S"""
  Parses a line from the client

  This is called from the user of this endpoint, not at MOM, for example from
  the WebSockets implementation.

  Returns:

  * :ok -- parsed and in processing
  * {:error, :bad_protocol} -- Invalid message, maybe not json, maybe not proper fields.
  """
  def parse_line(client, line) do
    case line do
      '' ->
        :empty
      line ->
        case JSON.decode( line ) do
          # these two are from the JSON side to the other side
          {:ok, %{ "method" => method, "params" => params, "id" => id}} ->
            call_out(client, method, params, id)
          {:ok, %{ "method" => method, "params" => params}} ->
            call_out(client, method, params, nil)

          # this are answers from JSON side to the other side
          {:ok, %{ "result" => result, "id" => id}} ->
            reply_in(client, result, id)
          {:ok, %{ "error" => error, "id" => id}} ->
            error_in(client, error, id)

          # no idea, should close.
          _ ->
            {:error, :bad_protocol}
        end
    end
  end

  # Call from JSON
  defp call_out(client, method, params, nil) do
    Channel.send(client.rpc_out.request, %MOM.Message{
      payload: %MOM.RPC.Message{ method: method, params: params },
      } )
    :ok
  end
  defp call_out(client, method, params, id) do
    case Channel.send(client.rpc_out.request, %MOM.Message{
      payload: %MOM.RPC.Message{ method: method, params: params },
      id: id
      } ) do
        :ok -> :ok
        :nok ->
          Channel.send(client.rpc_out.reply, %MOM.Message{
            id: id,
            error: :unknown_method
            })
          :ok
    end
  end
  # reply to JSON
  defp reply_out(client, result, id) do
    write_map(client, %{ result: result, id: id } )
  end
  # error to JSON
  defp error_out(client, error, id) do
    write_map(client, %{ error: error, id: id } )
  end

  # Call to JSON
  defp call_in(client, method, params, id) do
    jmsg = if id do
      %{
        method: method,
        params: params,
        id: id
      }
    else
      %{
        method: method,
        params: params
      }
    end

    write_map(client, jmsg)
  end
  # Reply from JSON
  defp reply_in(client, result, id) do
    Channel.send(client.rpc_in.reply, %MOM.Message{
      id: id,
      payload: result
      })
  end
  # Error from JSON
  defp error_in(client, error, id) do
    Channel.send(client.rpc_in.reply, %MOM.Message{
      id: id,
      error: error
      })
  end

  defp write_map(%{writef: writef}, map) do
    {:ok, line} = JSON.encode( map )
    writef.(line<>"\n")
  end

end
