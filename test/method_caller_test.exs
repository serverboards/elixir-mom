require Logger

defmodule Serverboards.MethodCallerTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log
  # doctest MOM.RPC.MethodCaller, import: true

  alias MOM.RPC

  test "Simple method caller v2" do
    {:ok, mc} = RPC.MethodCaller.start_link(name: :test)
    context = %{}
    mypid = self()

    RPC.MethodCaller.add_method(mc, "echo", & &1)
    RPC.MethodCaller.add_method(mc, "tac", fn str -> String.reverse(str) end)

    RPC.MethodCaller.add_method(
      mc,
      "same_pid",
      fn [], _context ->
        self() == mypid
      end,
      context: true
    )

    echo = RPC.MethodCaller.lookup(mc, "echo")
    Logger.debug("echo #{inspect(echo)}")

    dir = RPC.MethodCaller.dir(mc, context)
    Logger.debug("All methods #{inspect(dir)}")

    res = RPC.MethodCaller.call(mc, "echo", ["test"], context)
    assert res == {:ok, ["test"]}

    res = RPC.MethodCaller.call(mc, "tac", "tset", context)
    assert res == {:ok, "test"}

    {:ok, res} = RPC.MethodCaller.call(mc, "same_pid", [], context)
    assert res
  end

  test "Simple nested method caller" do
    import MOM.RPC.MethodCaller

    {:ok, mc} = RPC.MethodCaller.start_link(name: :test)
    {:ok, mc2} = RPC.MethodCaller.start_link(name: :test2)
    {:ok, mc3} = RPC.MethodCaller.start_link(name: :test3)
    context = %{}

    add_method(mc, "echo", & &1)
    add_method(mc, "tac", fn str -> String.reverse(str) end)

    add_method(
      mc,
      "get_context",
      fn [], context ->
        context
      end,
      context: true
    )

    add_method_caller(mc, mc2)
    add_method_caller(mc, mc3)

    add_method(mc2, "echo2", & &1)
    add_method(mc3, "echo3", & &1)

    dir = RPC.MethodCaller.dir(mc, context)
    Logger.debug("All methods #{inspect(dir)}")

    assert call(mc, "echo", "Hello world", context) == {:ok, "Hello world"}
    assert call(mc, "tac", "Hello world", context) == {:ok, "dlrow olleH"}
    assert call(mc, "get_context", [], context) == {:ok, context}
    assert call(mc, "echo2", "Hello world", context) == {:ok, "Hello world"}
    assert call(mc, "echo3", "Hello world", context) == {:ok, "Hello world"}
    assert call(mc, "echo4", "Hello world", context) == {:error, :unknown_method}
  end

  test "Methods with errors" do
    import MOM.RPC.MethodCaller
    {:ok, mc} = RPC.MethodCaller.start_link(name: :test)
    context = %{}

    add_method(mc, "echo", & &1)
    add_method(mc, "tac", fn [str] -> String.reverse(str) end)

    add_method(
      mc,
      "get_context",
      fn [], context ->
        context
      end,
      context: true
    )

    assert call(mc, "echo", "Hello world", context) == {:ok, "Hello world"}
    {:error, _} = call(mc, "tac", "Hello world", context)
    assert call(mc, "get_context", [], context) == {:ok, context}
    {:error, _} = call(mc, "echo_mc", "Hello world", context)
    assert call(mc, "echo_mc3", "Hello world", context) == {:error, :unknown_method}
  end

  test "Complex method handlers, many calls" do
    import MOM.RPC.MethodCaller
    context = %{}
    {:ok, mc} = RPC.MethodCaller.start_link(name: :mc)
    {:ok, mc1} = RPC.MethodCaller.start_link(name: :mc1)
    {:ok, mc11} = RPC.MethodCaller.start_link(name: :mc11)
    {:ok, mc12} = RPC.MethodCaller.start_link(name: :mc12)
    {:ok, mc2} = RPC.MethodCaller.start_link(name: :mc2)
    {:ok, mc21} = RPC.MethodCaller.start_link(name: :mc21)
    {:ok, mc22} = RPC.MethodCaller.start_link(name: :mc22)
    {:ok, mc211} = RPC.MethodCaller.start_link(name: :mc211)

    add_method_caller(mc, mc1)
    add_method_caller(mc1, mc11)
    add_method_caller(mc1, mc12)
    add_method_caller(mc, mc2)
    add_method_caller(mc2, mc21)
    add_method_caller(mc2, mc22)
    add_method_caller(mc21, mc211)

    add_method(mc, "mc", &{:ok, &1})
    add_method(mc1, "mc1", &{:ok, &1})
    add_method(mc11, "mc11", &{:ok, &1})
    add_method(mc12, "mc12", &{:ok, &1})
    add_method(mc2, "mc2", &{:ok, &1})
    add_method(mc21, "mc21", &{:ok, &1})
    add_method(mc22, "mc22", &{:ok, &1})
    add_method(mc22, "mc22_", &{:ok, &1})
    add_method(mc211, "mc211", &{:ok, &1})

    create_rec_method_caller = fn name ->
      {:ok, mc} = RPC.MethodCaller.start_link(name: String.to_atom(name))

      add_method(mc, name, fn [msg] ->
        {:ok, "#{name}_#{msg}"}
      end)

      mc
    end

    # Basic test, fn_method_caller works

    add_method_caller(mc, create_rec_method_caller.("fc"))
    add_method_caller(mc, create_rec_method_caller.("fc_1"))
    add_method_caller(mc1, create_rec_method_caller.("fc1"))
    add_method_caller(mc2, create_rec_method_caller.("fc2"))
    add_method_caller(mc21, create_rec_method_caller.("fc21"))
    add_method_caller(mc21, create_rec_method_caller.("fc21_1"))
    add_method_caller(mc211, create_rec_method_caller.("fc211"))
    add_method_caller(mc, create_rec_method_caller.("fc_2"))

    Logger.warn("Complex router")
    # simple call to complex router
    # and now call everything
    tini = :erlang.timestamp()
    ncalls = 10_000

    for i <- 1..ncalls do
      assert call(mc, "mc", [i * 1], context) == {:ok, [i * 1]}
      assert call(mc, "mc1", [i * 2], context) == {:ok, [i * 2]}
      assert call(mc, "mc11", [i * 3], context) == {:ok, [i * 3]}
      assert call(mc, "mc12", [i * 4], context) == {:ok, [i * 4]}
      assert call(mc, "mc2", [i * 5], context) == {:ok, [i * 5]}
      assert call(mc, "mc21", [i * 6], context) == {:ok, [i * 6]}
      assert call(mc, "mc22", [i * 7], context) == {:ok, [i * 7]}
      assert call(mc, "mc22_", [i * 8], context) == {:ok, [i * 8]}
      assert call(mc, "mc211", [i * 9], context) == {:ok, [i * 9]}
      assert call(mc, "mc211", [i * 10], context) == {:ok, [i * 10]}

      assert call(mc, "fc", [i * 1], context) == {:ok, "fc_#{i * 1}"}
      assert call(mc, "fc_1", [i * 2], context) == {:ok, "fc_1_#{i * 2}"}
      assert call(mc, "fc1", [i * 3], context) == {:ok, "fc1_#{i * 3}"}
      assert call(mc, "fc2", [i * 4], context) == {:ok, "fc2_#{i * 4}"}
      assert call(mc, "fc21", [i * 5], context) == {:ok, "fc21_#{i * 5}"}
      assert call(mc, "fc21_1", [i * 6], context) == {:ok, "fc21_1_#{i * 6}"}
      assert call(mc, "fc211", [i * 7], context) == {:ok, "fc211_#{i * 7}"}
      assert call(mc, "fc_2", [i * 8], context) == {:ok, "fc_2_#{i * 8}"}
      assert call(mc, "fc211", [i * 9], context) == {:ok, "fc211_#{i * 9}"}
      assert call(mc, "fc_2", [i * 10], context) == {:ok, "fc_2_#{i * 10}"}
    end

    tend = :erlang.timestamp()
    tdiff = :timer.now_diff(tend, tini) / 1_000_000
    ncalls = ncalls * 20

    IO.puts(
      "\n20_000 RPC calls in #{tdiff}s, #{ncalls / tdiff} call/s (with asserts, recs calls and some calculations)\n"
    )
  end

  @tag timeout: 90_000
  test "Basic method caller benchmark" do
    Logger.debug("Mem total: #{inspect(:erlang.memory()[:total], pretty: true)}")

    context = %{}
    {:ok, mc} = RPC.MethodCaller.start_link(name: :mc)

    {{tbig, tsmall}, ttotal} =
      MOM.Test.benchmark(fn ->
        bigdata =
          for n <- 0..100_000 do
            {:ok, n, "This is bigdata"}
          end

        Logger.debug("Data is #{:erts_debug.size(bigdata)} bytes #{inspect(hd(bigdata))}")
        Logger.debug("Memtotal: #{inspect(:erlang.memory()[:total], pretty: true)}")

        RPC.MethodCaller.add_method(mc, "benchbig", fn bigdata ->
          {:ok, Enum.count(bigdata)}
        end)

        ncalls = 500_000

        {_, tbig} =
          MOM.Test.benchmark(fn ->
            Enum.reduce(1..ncalls, 0, fn _acc, _n ->
              RPC.MethodCaller.call(mc, "test", [bigdata], context)
            end)
          end)

        IO.puts("Bigdata #{ncalls} calls in #{tbig}s. #{ncalls / tbig} calls/s")
        Logger.debug("Bigdata #{ncalls} calls in #{tbig}s. #{ncalls / tbig} calls/s")
        Logger.debug("Bigdata Memtotal #{inspect(:erlang.memory()[:total], pretty: true)}")

        {_, tsmall} =
          MOM.Test.benchmark(fn ->
            smalldata = hd(bigdata)

            Enum.reduce(1..ncalls, 0, fn _acc, _n ->
              RPC.MethodCaller.call(mc, "test", smalldata, context)
            end)
          end)

        IO.puts("Smalldata #{ncalls} calls in #{tsmall}s. #{ncalls / tsmall} calls/s")
        Logger.debug("Smalldata #{ncalls} calls in #{tsmall}s. #{ncalls / tsmall} calls/s")
        Logger.debug("Smalldata Memtotal #{inspect(:erlang.memory()[:total], pretty: true)}")

        {tbig, tsmall}
      end)

    Logger.debug("Total time #{inspect(ttotal)}s / ratio #{tbig / tsmall}")

    Logger.debug(
      "This checks that there is no copious copying of data, " <>
        "as actually no data copy should occur, and so it should " <>
        "take the same time do both tests"
    )

    assert tbig / tsmall < 10,
           "Tbig sould not be more than 10 times slower than tsmall (Its #{tbig / tsmall})"
  end

  def guard_perms(:kipple, context, options) do
    Logger.debug("Check guard for #{inspect(context)} / #{inspect(options[:perms])}")

    # ensure all perms in required are in context
    allow =
      Enum.all?(Access.get(options, :perms, []), fn p ->
        Enum.member?(context.perms, p)
      end)

    if allow do
      true
    else
      :permission_denied
    end
  end

  def echo(args, context) do
    Logger.debug("Echo #{inspect(args)} #{inspect(context)}")
    Agent.update(context.ncalls, fn n -> n + 1 end)
    args
  end

  test "Guards and context" do
    {:ok, mc} = MOM.RPC.MethodCaller.start_link()
    {:ok, ncalls} = Agent.start_link(fn -> 0 end)

    MOM.RPC.MethodCaller.add_guard(
      mc,
      {__MODULE__, :guard_perms, [:kipple]}
    )

    MOM.RPC.MethodCaller.add_method(mc, "test", &echo/2, perms: ["a"], context: true)

    res = MOM.RPC.MethodCaller.call(mc, "test", ["test"], %{perms: ["a", "b"], ncalls: ncalls})
    Logger.debug("res #{inspect(res)}")

    assert Agent.get(ncalls, & &1) == 1
    assert res == {:ok, ["test"]}

    MOM.RPC.MethodCaller.add_method(
      mc,
      "test2",
      fn args ->
        echo(args, %{ncalls: ncalls})
      end,
      perms: ["a"]
    )

    res = MOM.RPC.MethodCaller.call(mc, "test2", ["test"], %{perms: ["b"], ncalls: ncalls})
    Logger.debug("res #{inspect(res)}")

    assert Agent.get(ncalls, & &1) == 1
    assert res == {:error, :permission_denied}

    res = MOM.RPC.MethodCaller.call(mc, "dir", [], %{ncalls: ncalls, perms: []})
    Logger.debug("Call dir no perms #{inspect(res)}")
    assert res == {:ok, ["dir"]}
  end
end
