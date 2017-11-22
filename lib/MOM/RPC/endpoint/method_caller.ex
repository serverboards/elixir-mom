require Logger

defmodule MOM.RPC.Endpoint.MethodCaller do
  alias MOM.Channel
  alias MOM.RPC

  def start_link(rpc_in, options \\ []) do

    method_caller = if options[:method_caller] do
      options[:method_caller]
    else
      {:ok, method_caller} = MOM.RPC.MethodCaller.start_link
      method_caller
    end

    client = %{
      rpc_in: rpc_in,
      method_caller: method_caller,
      context: options[:context]
    }
    # I will receive requests here
    Channel.subscribe(rpc_in.request, fn msg ->
      res = RPC.MethodCaller.call(
        client.method_caller,
        msg.payload.method, msg.payload.params, client.context)

      if msg.id do
        case res do
          {:ok, reply} ->
            MOM.Channel.send( rpc_in.reply,
              %MOM.Message{ id: msg.id, payload: reply} )
          {:error, :unknown_method} ->
            :nok
          {:error, error} ->
            MOM.Channel.send( rpc_in.reply,
              %MOM.Message{ id: msg.id, error: error} )
        end
      else
        :ok
      end
    end)

    {:ok, client}
  end

  def stop(caller, reason \\ :normal) do
    RPC.MethodCaller.stop(caller.method_caller, reason)
  end

  def add_method_caller(client, mc, options \\ []) do
    RPC.MethodCaller.add_method_caller(client.method_caller, mc, options)
  end

  def add_method(client, name, method, options \\ []) do
    RPC.MethodCaller.add_method(client.method_caller, name, method, options)
  end
end
