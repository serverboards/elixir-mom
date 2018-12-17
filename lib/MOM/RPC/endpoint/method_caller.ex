require Logger

defmodule MOM.RPC.EndPoint.MethodCaller do
  use GenServer

  def start_link(endpoint, options \\ []) do
    {:ok, mc} = MOM.RPC.MethodCaller.start_link(options)

    MOM.RPC.EndPoint.update_in(endpoint, fn
      %MOM.RPC.Request{method: method, params: params, context: context} ->
        MOM.RPC.MethodCaller.call(mc, method, params, context)
      end, monitor: mc)

    {:ok, mc}
  end

  def add_method(mc, method, func, options \\ []) do
    MOM.RPC.MethodCaller.add_method(mc, method, func, options)
  end
  def add_method_caller(mc, mc2) do
    MOM.RPC.MethodCaller.add_method_caller(mc, mc2)
  end
end
