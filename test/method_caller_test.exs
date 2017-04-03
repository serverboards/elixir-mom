require Logger

defmodule Serverboards.MethodCallerTest do
  use ExUnit.Case
  @moduletag :capture_log
  doctest MOM.RPC.MethodCaller, import: true

	alias MOM.RPC

	test "Simple method caller" do
    import MOM.RPC.MethodCaller

    {:ok, mc} = RPC.MethodCaller.start_link name: :test
    {:ok, context} = RPC.Context.start_link

    add_method mc, "echo", &(&1)
    add_method mc, "tac", fn str -> String.reverse str end
    add_method mc, "get_context", fn [], context ->
      context
    end, context: true

    add_method_caller mc, fn msg ->
      case msg.method do
        "dir" ->
          {:ok, ["echo_mc"]}
        "echo_mc" ->
          {:ok, msg.params}
        _ -> :nok
      end
    end

    add_method_caller mc, fn msg ->
      case msg.method do
        "dir" ->
          {:ok, ["echo_mc2"]}
        "echo_mc2" ->
          {:ok, msg.params}
        _ -> :nok
      end
    end

    assert (call mc, "echo", "Hello world", context) == {:ok, "Hello world"}
    assert (call mc, "tac", "Hello world", context) == {:ok, "dlrow olleH"}
    assert (call mc, "get_context", [], context) == {:ok, context}
    assert (call mc, "echo_mc", "Hello world", context) == {:ok, "Hello world"}
    assert (call mc, "echo_mc2", "Hello world", context) == {:ok, "Hello world"}
    assert (call mc, "echo_mc3", "Hello world", context) == {:error, :unknown_method}
  end

  test "Methods with errors" do
    import MOM.RPC.MethodCaller
    {:ok, mc} = RPC.MethodCaller.start_link name: :test
    {:ok, context} = RPC.Context.start_link

    add_method mc, "echo", &(&1)
    add_method mc, "tac", fn [str] -> String.reverse str end
    add_method mc, "get_context", fn [], context ->
      context
    end, context: true

    add_method_caller mc, fn msg ->
      case msg.method do
        "dir" ->
          {:ok, ["echo_mc"]}
        "echo_mc" ->
          {:ok, msg.parms} # error on pourpose
        _ -> :nok
      end
    end

    add_method_caller mc, fn msg ->
      case msg.method do
        "dir" ->
          {:ok, ["echo_mc2"]}
        "echo_mc2" ->
          {:ok, {msg.params, msg.context}}
        _ -> :nok
      end
    end

    assert (call mc, "echo", "Hello world", context) == {:ok, "Hello world"}
    {:error, _} = (call mc, "tac", "Hello world", context)
    assert (call mc, "get_context", [], context) == {:ok, context}
    {:error, _} = (call mc, "echo_mc", "Hello world", context)
    assert (call mc, "echo_mc2", "Hello world", context) == {:ok, {"Hello world", context}}
    assert (call mc, "echo_mc3", "Hello world", context) == {:error, :unknown_method}
  end

  test "Complex method handlers, many calls" do
    import MOM.RPC.MethodCaller
    {:ok, context} = RPC.Context.start_link
    {:ok, mc} = RPC.MethodCaller.start_link
    {:ok, mc1} = RPC.MethodCaller.start_link
    {:ok, mc11} = RPC.MethodCaller.start_link
    {:ok, mc12} = RPC.MethodCaller.start_link
    {:ok, mc2} = RPC.MethodCaller.start_link
    {:ok, mc21} = RPC.MethodCaller.start_link
    {:ok, mc22} = RPC.MethodCaller.start_link
    {:ok, mc211} = RPC.MethodCaller.start_link

    add_method_caller mc, mc1
    add_method_caller mc1, mc11
    add_method_caller mc1, mc12
    add_method_caller mc, mc2
    add_method_caller mc2, mc21
    add_method_caller mc2, mc22
    add_method_caller mc21, mc211

    add_method mc, "mc", &(&1)
    add_method mc1, "mc1", &(&1)
    add_method mc11, "mc11", &(&1)
    add_method mc12, "mc12", &(&1)
    add_method mc2, "mc2", &(&1)
    add_method mc21, "mc21", &(&1)
    add_method mc22, "mc22", &(&1)
    add_method mc22, "mc22_", &(&1)
    add_method mc211, "mc211", &(&1)

    create_fn_method_caller = fn name ->
      fn msg ->
        #Logger.debug("At #{name}, msg #{inspect msg}")
        case msg do
          %{method: ^name} -> {:ok, name}
          _ -> :nok
        end
      end
    end

    add_method_caller mc, create_fn_method_caller.("mc_")
    add_method_caller mc, create_fn_method_caller.("mc_1")
    add_method_caller mc1, create_fn_method_caller.("mc1_")
    add_method_caller mc2, create_fn_method_caller.("mc2_")
    add_method_caller mc21, create_fn_method_caller.("mc21_")
    add_method_caller mc21, create_fn_method_caller.("mc21_1")
    add_method_caller mc211, create_fn_method_caller.("mc211_")
    add_method_caller mc, create_fn_method_caller.("mc_2")

    # and now call everything
    tini = :erlang.timestamp
    for _ <- 1..1_000 do
      assert (call mc, "mc", [], context) == {:ok, []}
      assert (call mc, "mc1", [], context) == {:ok, []}
      assert (call mc, "mc11", [], context) == {:ok, []}
      assert (call mc, "mc12", [], context) == {:ok, []}
      assert (call mc, "mc2", [], context) == {:ok, []}
      assert (call mc, "mc21", [], context) == {:ok, []}
      assert (call mc, "mc22", [], context) == {:ok, []}
      assert (call mc, "mc22_", [], context) == {:ok, []}
      assert (call mc, "mc211", [], context) == {:ok, []}
      assert (call mc, "mc211", [], context) == {:ok, []}

      assert (call mc, "mc_", [], context) == {:ok, "mc_"}
      assert (call mc, "mc_1", [], context) == {:ok, "mc_1"}
      assert (call mc, "mc1_", [], context) == {:ok, "mc1_"}
      assert (call mc, "mc2_", [], context) == {:ok, "mc2_"}
      assert (call mc, "mc21_", [], context) == {:ok, "mc21_"}
      assert (call mc, "mc21_1", [], context) == {:ok, "mc21_1"}
      assert (call mc, "mc211_", [], context) == {:ok, "mc211_"}
      assert (call mc, "mc_2", [], context) == {:ok, "mc_2"}
      assert (call mc, "mc211_", [], context) == {:ok, "mc211_"}
      assert (call mc, "mc_2", [], context) == {:ok, "mc_2"}
    end
    tend = :erlang.timestamp
    tdiff=:timer.now_diff(tend, tini)
    Logger.info("20_000 RPC calls in #{tdiff / 1000.0} ms, #{20_000 / (tdiff / 1_000_000)} call/s")
  end

  # Checks a strange bug, explained at MethodCaller.cast_mc
  test "Bug RPC mc :nok, :ok" do
    {:ok, rpc} = RPC.start_link
    {:ok, rpc_mc} = RPC.Endpoint.MethodCaller.start_link(rpc)
    {:ok, caller} = RPC.Endpoint.Caller.start_link(rpc)
    {:ok, mc} = RPC.MethodCaller.start_link
    {:ok, mc2} = RPC.MethodCaller.start_link

    RPC.Endpoint.MethodCaller.add_method_caller rpc_mc, mc
    #RPC.add_method_caller rpc, mc2

    RPC.MethodCaller.add_method mc, "foo", fn _ ->
      {:error, :why_you_call_me}
    end

    RPC.MethodCaller.add_method_caller mc, fn _ ->
      Logger.debug("Will not resolve it")
      :timer.sleep(100) # slow process
      :nok
    end, name: :fail
    RPC.MethodCaller.add_method_caller mc, mc2, name: :mc2
    RPC.MethodCaller.add_method mc2, "test", fn _ ->
      :timer.sleep(200) # slow process
      {:ok, :ok}
    end

    assert (RPC.Endpoint.Caller.call caller, "test", []) == {:ok, :ok}
  end

  # from http://stackoverflow.com/questions/29668635/how-can-we-easily-time-function-calls-in-elixir
  def measure(function) do
    function
    |> :timer.tc
    |> elem(0)
    |> Kernel./(1_000_000)
  end


  test "Calls are not serialized" do
    {:ok, rpc} = RPC.start_link
    {:ok, rpc_mc} = RPC.Endpoint.MethodCaller.start_link(rpc)
    {:ok, caller} = RPC.Endpoint.Caller.start_link(rpc)
    {:ok, mc} = RPC.MethodCaller.start_link
    RPC.Endpoint.MethodCaller.add_method_caller rpc_mc, mc

      RPC.MethodCaller.add_method mc, "foo", fn _ ->
        Logger.debug("Wait 2s #{inspect self()}")
        :timer.sleep(2_000)
        {:ok, :ok}
      end

    # one call, sync, for control
    t = measure(fn ->
      assert (RPC.Endpoint.Caller.call caller, "foo", []) == {:ok, :ok}
    end)
    assert t > 2
    assert t < 3

    Logger.debug("Do 100")

    # 10 real test
    t = measure(fn ->
      for i <- 1..100 do
        Task.async(fn ->
          RPC.Endpoint.Caller.call(caller, "foo", [])
        end)
      end |> Enum.map(fn t ->
        Task.await(t)
      end)
    end)
    assert t > 2
    assert t < 3

    Logger.debug("Done")
  end

end
