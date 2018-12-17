require Logger

defmodule Serverboards.RPCTest do
  use ExUnit.Case
  @moduletag :capture_log
  doctest MOM.RPC.Context, import: true

  alias MOM.RPC
  alias MOM.RPC.EndPoint
  alias MOM.RPC.EndPoint.Caller
	alias MOM.RPC.EndPoint.MethodCaller

  @tag timeout: 1_000
  test "RPC create then connect" do
    mc_ep = EndPoint.new()
    io_ep = EndPoint.new()
    {:ok, mc} = MethodCaller.start_link(mc_ep)
    {:ok, caller} = Caller.start_link(io_ep)

    EndPoint.connect(mc_ep, io_ep)

    RPC.MethodCaller.add_method(mc, "echo", &({:ok, &1}))

    res = Caller.call(caller, "echo", "test")
    Logger.debug("Echo res: #{inspect res}")
    assert res == {:ok, "test"}
  end

  @tag timeout: 1_000
  test "RPC pair" do
    {mc_ep, io_ep} = EndPoint.pair()
    {:ok, mc} = MethodCaller.start_link(mc_ep)
    {:ok, caller} = Caller.start_link(io_ep)

    RPC.MethodCaller.add_method(mc, "echo", &({:ok, &1}))

    res = Caller.call(caller, "echo", "test")
    Logger.debug("Echo res: #{inspect res}")
    assert res == {:ok, "test"}

    assert Caller.call(caller, "dir", []) == {:ok, ["dir", "echo"]}
    assert Caller.call(caller, "not-exists", []) == {:error, :unknown_method}
  end

  @tag timeout: 1_000
  test "RPC two method callers chained, and error unknown_method" do
    {mc_ep, io_ep} = EndPoint.pair()
    {:ok, mc} = MethodCaller.start_link(mc_ep)
    {:ok, caller} = Caller.start_link(io_ep)
    {:ok, mc2} = MethodCaller.start_link(mc_ep)

    RPC.MethodCaller.add_method(mc, "echo", &({:ok, &1}))
    RPC.MethodCaller.add_method(mc2, "echo2", &({:ok, &1}))

    assert Caller.call(caller, "echo", "test") == {:ok, "test"}
    assert Caller.call(caller, "echo2", "test") == {:ok, "test"}

    assert Caller.call(caller, "not-exists", []) == {:error, :unknown_method}
  end

  @tag timeout: 1_000
  test "Nested method callers" do
    {mc_ep, io_ep} = EndPoint.pair()
    {:ok, mc} = MethodCaller.start_link(mc_ep)
    {:ok, caller} = Caller.start_link(io_ep)

    {:ok, mc2} = MOM.RPC.MethodCaller.start_link()

    MOM.RPC.MethodCaller.add_method_caller(mc, mc2)
    RPC.MethodCaller.add_method(mc, "echo", &({:ok, &1}))
    RPC.MethodCaller.add_method(mc2, "echo2", &({:ok, &1}))

    assert Caller.call(caller, "echo", "test") == {:ok, "test"}
    assert Caller.call(caller, "echo2", "test") == {:ok, "test"}
    assert Caller.call(caller, "dir", []) == {:ok, ["dir", "echo", "echo2"]}
  end


	test "Simple RPC use" do
		{endpoint_a, endpoint_b} = EndPoint.pair()
    {:ok, caller } = Caller.start_link(endpoint_a)
    {:ok, mc } = MethodCaller.start_link(endpoint_b)
		EndPoint.tap( endpoint_a )

		MethodCaller.add_method mc, "echo", &(&1), async: true

		# simple direct call
		assert EndPoint.Caller.call(caller, "echo", "hello") == {:ok, "hello"}

		# call unknown
		assert EndPoint.Caller.call(caller, "pong", nil) == {:error, :unknown_method}
	end


  test "RPC method with pattern matching" do
    {endpoint_a, endpoint_b} = EndPoint.pair()
    {:ok, caller } = Caller.start_link(endpoint_a)
    {:ok, mc } = MethodCaller.start_link(endpoint_b)

    EndPoint.tap( endpoint_a )

    EndPoint.MethodCaller.add_method mc, "echo", fn
      [_] -> "one item"
      [] -> "empty"
      %{ type: _ } -> {:ok, "map with type"}
    end, async: true

    assert EndPoint.Caller.call(caller, "echo", []) == {:ok, "empty"}
    assert EndPoint.Caller.call(caller, "echo", [1]) == {:ok, "one item"}
    assert EndPoint.Caller.call(caller, "echo", %{}) == {:error, :bad_arity}
    assert EndPoint.Caller.call(caller, "echo", %{ type: :test}) == {:ok, "map with type"}
  end


  test "Long running RPC call" do
    IO.puts("Wait 10 secs. No timeouts anywhere.")
    {endpoint_a, endpoint_b} = EndPoint.pair()
    {:ok, caller } = Caller.start_link(endpoint_a)
    {:ok, mc } = MethodCaller.start_link(endpoint_b)

    EndPoint.MethodCaller.add_method mc, "wait", fn [] ->
      Process.sleep(10_000)
      :ok
    end

    assert EndPoint.Caller.call(caller, "wait", []) == {:ok, :ok}
  end
end
