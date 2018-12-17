require Logger

defmodule Serverboards.RPCTest do
  use ExUnit.Case
  @moduletag :capture_log
  doctest MOM.RPC
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
  end


	test "Simple RPC use" do
		{:ok, rpc} = RPC.start_link
    {:ok, caller } = EndPoint.Caller.start_link(rpc)
    {:ok, mc } = EndPoint.MethodCaller.start_link(rpc)
		RPC.tap( rpc )

		EndPoint.MethodCaller.add_method mc, "echo", &(&1), async: true

		# simple direct call
		assert EndPoint.Caller.call(caller, "echo", "hello") == {:ok, "hello"}

		# simple call through chain
		{:ok, worker} = RPC.start_link
    {:ok, mcw} = EndPoint.MethodCaller.start_link(worker)
		RPC.tap( worker )

		EndPoint.MethodCaller.add_method mcw, "ping", fn _ ->
			"pong"
		end
		RPC.chain rpc, worker
		assert EndPoint.Caller.call(caller, "ping", []) == {:ok, "pong"}

		# call unknown
		assert EndPoint.Caller.call(caller, "pong", nil) == {:error, :unknown_method}

		# chain a second worker
		{:ok, worker2} = RPC.start_link
    {:ok, mcw2} = EndPoint.MethodCaller.start_link(worker2)
		RPC.tap( worker2 )
		EndPoint.MethodCaller.add_method mcw2, "pong", fn _ ->
			"pong"
		end

		# still not chained, excpt
		assert EndPoint.Caller.call(caller, "pong", nil) == {:error, :unknown_method}

		# now works
		RPC.chain rpc, worker2
		assert EndPoint.Caller.call(caller, "pong", nil) == {:ok, "pong"}
	end


  test "RPC method with pattern matching" do
    {:ok, rpc} = RPC.start_link
    {:ok, caller } = EndPoint.Caller.start_link(rpc)
    {:ok, mc } = EndPoint.MethodCaller.start_link(rpc)

    RPC.tap( rpc )

    EndPoint.MethodCaller.add_method mc, "echo", fn
      [_] -> "one item"
      [] -> "empty"
      %{ type: _ } -> "map with type"
    end, async: true

    assert EndPoint.Caller.call(caller, "echo", []) == {:ok, "empty"}
    assert EndPoint.Caller.call(caller, "echo", [1]) == {:ok, "one item"}
    assert EndPoint.Caller.call(caller, "echo", %{}) == {:error, :bad_arity}
    assert EndPoint.Caller.call(caller, "echo", %{ type: :test}) == {:ok, "map with type"}
  end


  test "dir aggregates from all method callers and even calls remotes" do
    {:ok, rpc} = RPC.start_link
    {:ok, caller } = EndPoint.Caller.start_link(rpc)
    {:ok, mc } = EndPoint.MethodCaller.start_link(rpc)

    RPC.tap( rpc )

    EndPoint.MethodCaller.add_method mc, "echo", fn
      [_] -> "one item"
      [] -> "empty"
      %{ type: _ } -> "map with type"
    end, async: true

    {:ok, mc1} = RPC.MethodCaller.start_link
    RPC.MethodCaller.add_method mc1, "echo1", &(&1)

    {:ok, mc2} = RPC.MethodCaller.start_link
    RPC.MethodCaller.add_method mc2, "echo2", &(&1)

    {:ok, mc3} = RPC.MethodCaller.start_link
    RPC.MethodCaller.add_method mc2, "echo3", &(&1)

    EndPoint.MethodCaller.add_method_caller mc, mc1
    EndPoint.MethodCaller.add_method_caller mc, mc2
    RPC.MethodCaller.add_method_caller mc2, mc3

    assert EndPoint.Caller.call(caller, "dir", []) == {:ok, ~w(dir echo echo1 echo2 echo3)}
  end

  test "RPC function method callers" do
    {:ok, rpc} = RPC.start_link
    {:ok, caller } = EndPoint.Caller.start_link(rpc)
    {:ok, mc } = EndPoint.MethodCaller.start_link(rpc)

    EndPoint.MethodCaller.add_method_caller mc, fn msg ->
      case msg.method do
        "dir" ->
          {:ok, ["dir", "echo"]}
        "echo" ->
          {:ok, msg.params}
        _ ->
          :nok
      end
    end

    assert EndPoint.Caller.call(caller, "dir", []) == {:ok, ~w(dir echo)}
    assert EndPoint.Caller.call(caller, "echo", [1,2,3]) == {:ok, [1,2,3]}
  end

  test "Long running RPC call" do
    {:ok, rpc} = RPC.start_link
    {:ok, caller } = EndPoint.Caller.start_link(rpc)
    {:ok, mc } = EndPoint.MethodCaller.start_link(rpc)

    EndPoint.MethodCaller.add_method mc, "wait", fn [] ->
      Process.sleep(10000)
      :ok
    end

    assert EndPoint.Caller.call(caller, "wait", []) == {:ok, :ok}
  end
end
