require Logger

defmodule MOM.RPC.EndPoint.MethodCaller do
  use GenServer

  def new() do
    endpoint = MOM.RPC.EndPoint.new()
    {:ok, mc} = MOM.RPC.MethodCaller.start_link()

    endpoint = MOM.RPC.EndPoint.update_in(endpoint, fn
      %MOM.RPC.Request{method: method, params: params, context: context} = msg->
        # Logger.debug("Got method call #{inspect msg}")
        MOM.RPC.MethodCaller.call(mc, method, params, context)
      end, monitor: mc)

    {:ok, endpoint, mc}
  end
end
