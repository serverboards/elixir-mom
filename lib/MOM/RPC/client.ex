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

  def get(pid, what) do
    GenServer.call(pid, {:get, what})
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

  def parse_line(pid, line) do
    json = get(pid, :json)
    MOM.RPC.EndPoint.JSON.parse_line(json, line)
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

    # MOM.RPC.EndPoint.tap(ep1, "JSONa", "Caller")
    # MOM.RPC.EndPoint.tap(ep2, "JSONb", "MethodCaller")

    {:ok, caller} = MOM.RPC.EndPoint.Caller.start_link(ep1)

    {:ok, json} = MOM.RPC.EndPoint.JSON.start_link(ep12, options[:writef])

    # I can not call anybody
    {:ok, mc} = MOM.RPC.EndPoint.MethodCaller.start_link(ep2)

    {:ok,
     %{
       mc: mc,
       caller: caller,
       json: json
     }}
  end

  def handle_call({:get, something}, _from, status) do
    {:reply, status[something], status}
  end
end
