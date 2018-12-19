require Logger

defmodule MOM.RPC.Client do
  use GenServer

  @moduledoc ~S"""
  Simplify client creation using RPC endpoints.

  It creates the most common architecture for clients:

  1. Caller
  2. JSON Side
  3. Method Caller

  The are connected so that:

  1. Caller does the calls into the JSON side
  2. JSON Side does the calls to the Method Caller

  Caller <--->>> JSON <---->>> Method caller

  This module encapsulates most common methods:

  1. writef (callback) / parse_line
  2. call / event
  3. add_method / add_method_caller
  """

  @doc ~S"""
  Start the client. Requires the writef function at options.
  """
  def start_link(options) do
    if options[:writef] == nil do
      raise "MOM.RPC.Client requires a :writef option"
    end

    GenServer.start_link(__MODULE__, options, options)
  end

  def stop(pid, reason \\ :normal) do
    GenServer.stop(pid, reason)
  end

  def get(pid, what, defval \\ nil) do
    case GenServer.call(pid, {:get, what}) do
      nil ->
        defval

      val ->
        val
    end
  end

  def set(_pid, :caller, _value), do: raise("Cant set :caller")
  def set(_pid, :json, _value), do: raise("Cant set :json")
  def set(_pid, :mc, _value), do: raise("Cant set :mc")

  def set(pid, what, value) do
    GenServer.call(pid, {:set, what, value})
  end

  def update(_pid, :caller, _value), do: raise("Cant update :caller")
  def update(_pid, :json, _value), do: raise("Cant update :json")
  def update(_pid, :mc, _value), do: raise("Cant update :mc")

  def update(pid, what, how) do
    GenServer.call(pid, {:update, what, how})
  end

  def call(pid, method, args, timeout \\ 60_000) do
    caller = get(pid, :caller)
    MOM.RPC.EndPoint.Caller.call(caller, method, args, timeout)
  end

  def event(pid, method, args) do
    caller = get(pid, :caller)
    MOM.RPC.EndPoint.Caller.event(caller, method, args)
  end

  def add_method(pid, method, func, options \\ []) do
    mc = get(pid, :mc)
    MOM.RPC.EndPoint.MethodCaller.add_method(mc, method, func, options)
  end

  def add_method_caller(pid, mc2) do
    mc = get(pid, :mc)
    MOM.RPC.EndPoint.MethodCaller.add_method_caller(mc, mc2)
  end

  def add_guard(pid, guard) do
    mc = get(pid, :mc)
    MOM.RPC.EndPoint.MethodCaller.add_guard(mc, guard)
  end

  def parse_line(pid, line) do
    json = get(pid, :json)
    MOM.RPC.EndPoint.JSON.parse_line(json, line, pid)
  end

  def tap(pid) do
    [ep1, ep2] = get(pid, [:ep1, :ep2])
    Logger.debug("Tap #{inspect({pid, ep1, ep2})}")
    MOM.RPC.EndPoint.tap(ep1, "JSONa", "Caller")
    MOM.RPC.EndPoint.tap(ep2, "JSONb", "MethodCaller")
  end

  # server impl
  def init(options) do
    # caller <->>> RPC
    ep1 = MOM.RPC.EndPoint.new()
    ep2 = MOM.RPC.EndPoint.new()

    ep12 = %MOM.RPC.EndPoint{
      in: ep1.out,
      out: ep2.in
    }

    {:ok, caller} = MOM.RPC.EndPoint.Caller.start_link(ep1)

    {mod, fun, args} = options[:writef]

    args = args ++ [self()]

    {:ok, json} = MOM.RPC.EndPoint.JSON.start_link(ep12, {mod, fun, args})

    # I can not call anybody
    {:ok, mc} = MOM.RPC.EndPoint.MethodCaller.start_link(ep2)

    :erlang.process_flag(:trap_exit, true)

    {:ok,
     %{
       mc: mc,
       caller: caller,
       json: json,
       ep1: ep1,
       ep2: ep2
     }}
  end

  def handle_call({:get, somethings}, _from, status) when is_list(somethings) do
    ret =
      for i <- somethings do
        status[i]
      end

    {:reply, ret, status}
  end

  def handle_call({:get, something}, _from, status) do
    {:reply, status[something], status}
  end

  def handle_call({:set, something, value}, _from, status) do
    {:reply, :ok, Map.put(status, something, value)}
  end

  def handle_call({:update, something, how}, _from, status) do
    newvalue = how.(status[something])
    {:reply, newvalue, Map.put(status, something, newvalue)}
  end

  def terminate(reason, state) do
    MOM.RPC.EndPoint.stop(state.ep1, reason)
    MOM.RPC.EndPoint.stop(state.ep2, reason)
    MOM.RPC.EndPoint.MethodCaller.stop(state.mc, reason)
    MOM.RPC.EndPoint.JSON.stop(state.json, reason)
    MOM.RPC.EndPoint.Caller.stop(state.caller, reason)
  end
end
