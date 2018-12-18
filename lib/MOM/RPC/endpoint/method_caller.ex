require Logger

defmodule MOM.RPC.EndPoint.MethodCaller do
  def start_link(endpoint, options \\ []) do
    {:ok, mc} = MOM.RPC.MethodCaller.start_link(options)

    MOM.RPC.EndPoint.update_in(
      endpoint,
      fn
        %MOM.RPC.Request{method: method, params: params, context: context} ->
          MOM.RPC.MethodCaller.call(mc, method, params, context)

        _ ->
          :wtf
      end,
      monitor: mc
    )

    {:ok, mc}
  end

  def stop(mc, reason \\ :normal) do
    GenServer.stop(mc, reason)
  end

  def add_method(mc, method, func, options \\ []) do
    MOM.RPC.MethodCaller.add_method(mc, method, func, options)
  end

  def add_method_caller(mc, mc2) do
    MOM.RPC.MethodCaller.add_method_caller(mc, mc2)
  end

  def add_guard(mc, guard) do
    MOM.RPC.MethodCaller.add_guard(mc, guard)
  end
end
