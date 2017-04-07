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
    {:ok, mc} = RPC.MethodCaller.start_link name: :"mc"
    {:ok, mc1} = RPC.MethodCaller.start_link name: :"mc1"
    {:ok, mc11} = RPC.MethodCaller.start_link name: :"mc11"
    {:ok, mc12} = RPC.MethodCaller.start_link name: :"mc12"
    {:ok, mc2} = RPC.MethodCaller.start_link name: :"mc2"
    {:ok, mc21} = RPC.MethodCaller.start_link name: :"mc21"
    {:ok, mc22} = RPC.MethodCaller.start_link name: :"mc22"
    {:ok, mc211} = RPC.MethodCaller.start_link name: :"mc211"

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
      fn
        %{method: ^name, params: [msg]} -> {:ok, "#{name}_#{msg}"}
        %{method: n} ->
          Logger.debug("NOK #{inspect name} != #{inspect n}")
           :nok
      end
    end

    # Basic test, fn_method_caller works
    assert (call create_fn_method_caller.("fc"), "fc", [8], context) == {:ok, "fc_8"}

    add_method_caller mc, create_fn_method_caller.("fc")
    add_method_caller mc, create_fn_method_caller.("fc_1")
    add_method_caller mc1, create_fn_method_caller.("fc1")
    add_method_caller mc2, create_fn_method_caller.("fc2")
    add_method_caller mc21, create_fn_method_caller.("fc21")
    add_method_caller mc21, create_fn_method_caller.("fc21_1")
    add_method_caller mc211, create_fn_method_caller.("fc211")
    add_method_caller mc, create_fn_method_caller.("fc_2")

    Logger.warn("Complex router")
    # simple call to complex router
    assert (call mc, "fc", [8], context) == {:ok, "fc_8"}
    Logger.warn("Ok 1")

    assert (call mc, "fc_2", [8], context) == {:ok, "fc_2_8"}
    Logger.warn("Ok 2")


    # and now call everything
    tini = :erlang.timestamp
    for i <- 1..1_000 do
      assert (call mc, "mc", [i*1], context) == {:ok, [i*1]}
      assert (call mc, "mc1", [i*2], context) == {:ok, [i*2]}
      assert (call mc, "mc11", [i*3], context) == {:ok, [i*3]}
      assert (call mc, "mc12", [i*4], context) == {:ok, [i*4]}
      assert (call mc, "mc2", [i*5], context) == {:ok, [i*5]}
      assert (call mc, "mc21", [i*6], context) == {:ok, [i*6]}
      assert (call mc, "mc22", [i*7], context) == {:ok, [i*7]}
      assert (call mc, "mc22_", [i*8], context) == {:ok, [i*8]}
      assert (call mc, "mc211", [i*9], context) == {:ok, [i*9]}
      assert (call mc, "mc211", [i*10], context) == {:ok, [i*10]}

      assert (call mc, "fc", [i*1], context) == {:ok, "fc_#{i*1}"}
      assert (call mc, "fc_1", [i*2], context) == {:ok, "fc_1_#{i*2}"}
      assert (call mc, "fc1", [i*3], context) == {:ok, "fc1_#{i*3}"}
      assert (call mc, "fc2", [i*4], context) == {:ok, "fc2_#{i*4}"}
      assert (call mc, "fc21", [i*5], context) == {:ok, "fc21_#{i*5}"}
      assert (call mc, "fc21_1", [i*6], context) == {:ok, "fc21_1_#{i*6}"}
      assert (call mc, "fc211", [i*7], context) == {:ok, "fc211_#{i*7}"}
      assert (call mc, "fc_2", [i*8], context) == {:ok, "fc_2_#{i*8}"}
      assert (call mc, "fc211", [i*9], context) == {:ok, "fc211_#{i*9}"}
      assert (call mc, "fc_2", [i*10], context) == {:ok, "fc_2_#{i*10}"}
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
      for _i <- 1..100 do
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
