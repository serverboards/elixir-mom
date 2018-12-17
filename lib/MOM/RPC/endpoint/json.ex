require Logger

defmodule MOM.RPC.EndPoint.JSON do
  alias MOM.Channel
  use GenServer


  @doc ~S"""
  Connects an RPC to do JSON communications

  * `options` are the options:
    * `writef` : f(str) to write to the remote side
  """
  def new(options) do
    writef = options[:writef]

    endpoint = MOM.RPC.EndPoint.new()
    {:ok, pid} = GenServer.start_link(__MODULE__, endpoint.out, options)

    # On RPC, any message in just goes to the other side
    MOM.RPC.EndPoint.update_in(endpoint, fn req_res ->
        write_map(writef, req_res)
    end)
    {:ok, pid}
  end

  def stop(pid, reason) do
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
    out = GenServer.call(client, {:get_out})
    case line do
      '' ->
        :empty
      line ->
        case Poison.decode( line ) do
          # these two are from the JSON side to the other side
          {:ok, %{ "method" => method, "params" => params, "id" => id}} ->
            MOM.Channel.send(out, %MOM.RPC.Request{method: method, params: params, id: id, context: context})
          {:ok, %{ "method" => method, "params" => params}} ->
            MOM.Channel.send(out, %MOM.RPC.Request{method: method, params: params, id: nil, context: context})

          # this are answers from JSON side to the other side
          {:ok, %{ "result" => result, "id" => id}} ->
            MOM.Channel.send(out, %MOM.RPC.Response{result: result, id: nil})
          {:ok, %{ "error" => error, "id" => id}} ->
            MOM.Channel.send(out, %MOM.RPC.Response.Error{error: error, id: nil})
          # no idea, should close.
          _ ->
            {:error, :bad_protocol}
        end
    end
  end

  defp write_map(writef, map) do
    {:ok, line} = Poison.encode(map)
    writef.(line<>"\n")
    :ok
  end

  ## Server impl

  def init(out) do
    {:ok, out}
  end

  def handle_call({:get_out}, _from, status) do
    {:reply, status, status}
  end
end
