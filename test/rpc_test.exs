defmodule Serverboards.RPCTest do
  use ExUnit.Case
  @moduletag :capture_log
  doctest MOM.RPC
  doctest MOM.RPC.Context, import: true

  alias MOM.RPC
	alias MOM.RPC.Endpoint

	test "Simple RPC use" do
		{:ok, rpc} = RPC.start_link
    {:ok, caller } = Endpoint.Caller.start_link(rpc)
    {:ok, mc } = Endpoint.MethodCaller.start_link(rpc)
		RPC.tap( rpc )

		Endpoint.MethodCaller.add_method mc, "echo", &(&1), async: true

		# simple direct call
		assert Endpoint.Caller.call(caller, "echo", "hello") == {:ok, "hello"}

		# simple call through chain
		{:ok, worker} = RPC.start_link
    {:ok, mcw} = Endpoint.MethodCaller.start_link(worker)
		RPC.tap( worker )

		Endpoint.MethodCaller.add_method mcw, "ping", fn _ ->
			"pong"
		end
		RPC.chain rpc, worker
		assert Endpoint.Caller.call(caller, "ping", []) == {:ok, "pong"}

		# call unknown
		assert Endpoint.Caller.call(caller, "pong", nil) == {:error, :unknown_method}

		# chain a second worker
		{:ok, worker2} = RPC.start_link
    {:ok, mcw2} = Endpoint.MethodCaller.start_link(worker2)
		RPC.tap( worker2 )
		Endpoint.MethodCaller.add_method mcw2, "pong", fn _ ->
			"pong"
		end

		# still not chained, excpt
		assert Endpoint.Caller.call(caller, "pong", nil) == {:error, :unknown_method}

		# now works
		RPC.chain rpc, worker2
		assert Endpoint.Caller.call(caller, "pong", nil) == {:ok, "pong"}
	end


  test "RPC method with pattern matching" do
    {:ok, rpc} = RPC.start_link
    {:ok, caller } = Endpoint.Caller.start_link(rpc)
    {:ok, mc } = Endpoint.MethodCaller.start_link(rpc)

    RPC.tap( rpc )

    Endpoint.MethodCaller.add_method mc, "echo", fn
      [_] -> "one item"
      [] -> "empty"
      %{ type: _ } -> "map with type"
    end, async: true

    assert Endpoint.Caller.call(caller, "echo", []) == {:ok, "empty"}
    assert Endpoint.Caller.call(caller, "echo", [1]) == {:ok, "one item"}
    assert Endpoint.Caller.call(caller, "echo", %{}) == {:error, :bad_arity}
    assert Endpoint.Caller.call(caller, "echo", %{ type: :test}) == {:ok, "map with type"}
  end


  test "dir aggregates from all method callers and even calls remotes" do
    {:ok, rpc} = RPC.start_link
    {:ok, caller } = Endpoint.Caller.start_link(rpc)
    {:ok, mc } = Endpoint.MethodCaller.start_link(rpc)

    RPC.tap( rpc )

    Endpoint.MethodCaller.add_method mc, "echo", fn
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

    Endpoint.MethodCaller.add_method_caller mc, mc1
    Endpoint.MethodCaller.add_method_caller mc, mc2
    RPC.MethodCaller.add_method_caller mc2, mc3

    assert Endpoint.Caller.call(caller, "dir", []) == {:ok, ~w(dir echo echo1 echo2 echo3)}
  end

  test "RPC function method callers" do
    {:ok, rpc} = RPC.start_link
    {:ok, caller } = Endpoint.Caller.start_link(rpc)
    {:ok, mc } = Endpoint.MethodCaller.start_link(rpc)

    Endpoint.MethodCaller.add_method_caller mc, fn msg ->
      case msg.method do
        "dir" ->
          {:ok, ["dir", "echo"]}
        "echo" ->
          {:ok, msg.params}
        _ ->
          :nok
      end
    end

    assert Endpoint.Caller.call(caller, "dir", []) == {:ok, ~w(dir echo)}
    assert Endpoint.Caller.call(caller, "echo", [1,2,3]) == {:ok, [1,2,3]}
  end
end
