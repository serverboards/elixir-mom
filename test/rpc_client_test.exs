require Logger

defmodule Serverboards.RPC.ClientTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  test "Bad protocol" do
    {ep1, ep2} = MOM.RPC.EndPoint.pair()
    {:ok, json} = MOM.RPC.EndPoint.JSON.start_link(ep1, nil)
    {:ok, _mc} = MOM.RPC.EndPoint.MethodCaller.start_link(ep2)

    {:error, :bad_protocol} = MOM.RPC.EndPoint.JSON.parse_line(json, "bad protocol")

    # Now a good call
    {:ok, mcjson} = Poison.encode(%{method: "dir", params: [], id: 1})
    :ok = MOM.RPC.EndPoint.JSON.parse_line(json, mcjson)

    MOM.RPC.EndPoint.stop(ep1)
  end

  def writef_last_line(context, line) do
    Logger.debug("Read>> #{line}")
    Agent.update(context, fn _ -> line end)
  end

  test "Good protocol" do
    {:ok, context} = Agent.start_link(fn -> nil end)
    {ep1, ep2} = MOM.RPC.EndPoint.pair()

    {:ok, json} =
      MOM.RPC.EndPoint.JSON.start_link(ep1, {__MODULE__, :writef_last_line, [context]})

    {:ok, _mcall} = MOM.RPC.EndPoint.MethodCaller.start_link(ep2)
    MOM.RPC.EndPoint.tap(ep1)

    {:ok, mc} = Poison.encode(%{method: "dir", params: [], id: 1})
    MOM.RPC.EndPoint.JSON.parse_line(json, mc, context)

    :timer.sleep(200)

    {:ok, json} = Poison.decode(Agent.get(context, & &1))
    Logger.debug(inspect(json))
    assert Map.get(json, "result") == ~w(dir)

    MOM.RPC.EndPoint.stop(ep1)
    Agent.stop(context)
  end

  test "Call to client" do
    {:ok, context} = Agent.start_link(fn -> nil end)
    {:ok, called} = Agent.start_link(fn -> false end)
    {ep1, ep2} = MOM.RPC.EndPoint.pair()
    MOM.RPC.EndPoint.tap(ep1)

    {:ok, json} =
      MOM.RPC.EndPoint.JSON.start_link(ep1, {__MODULE__, :writef_last_line, [context]})

    {:ok, caller} = MOM.RPC.EndPoint.Caller.start_link(ep2)

    Task.start(fn ->
      # waits to get answer, to set the called
      res = MOM.RPC.EndPoint.Caller.call(caller, "dir", [])
      assert res == {:ok, []}
      Agent.update(called, fn _ -> true end)
    end)

    # 20 ms
    :timer.sleep(20)

    # manual reply
    assert Agent.get(called, & &1) == false
    last_line = Agent.get(context, & &1)
    Logger.debug("Last line #{inspect(last_line)}")
    {:ok, js} = Poison.decode(last_line)
    assert Map.get(js, "method") == "dir"
    {:ok, res} = Poison.encode(%{id: 1, result: []})
    Logger.debug("Writing>> #{res}")
    assert MOM.RPC.EndPoint.JSON.parse_line(json, res) == :ok

    # 20ms
    :timer.sleep(20)

    assert Agent.get(called, & &1) == true

    MOM.RPC.EndPoint.Caller.event(caller, "auth", ["basic"])
    :timer.sleep(1)
    last_line = Agent.get(context, & &1)
    {:ok, js} = Poison.decode(last_line)
    assert Map.get(js, "method") == "auth"
    assert Map.get(js, "params") == ["basic"]
    assert Map.get(js, "id") == nil

    MOM.RPC.EndPoint.stop(ep1)
    MOM.RPC.EndPoint.JSON.stop(json)
    MOM.RPC.EndPoint.Caller.stop(caller)
  end

  test "Call from client" do
    {:ok, context} = Agent.start_link(fn -> nil end)
    {ep1, ep2} = MOM.RPC.EndPoint.pair()

    {:ok, json} =
      MOM.RPC.EndPoint.JSON.start_link(ep1, {__MODULE__, :writef_last_line, [context]})

    {:ok, caller} = MOM.RPC.EndPoint.Caller.start_link(ep2)
    MOM.RPC.EndPoint.tap(ep1)

    # events, have no reply never
    {:ok, jsline} = Poison.encode(%{method: "ready", params: []})
    assert MOM.RPC.EndPoint.JSON.parse_line(json, jsline) == :ok
    :timer.sleep(200)
    last_line = Agent.get(context, & &1)
    assert last_line == nil

    # method calls, have it, for example, unknown
    {:ok, jsline} = Poison.encode(%{method: "ready", params: [], id: 1})
    assert MOM.RPC.EndPoint.JSON.parse_line(json, jsline) == :ok
    :timer.sleep(200)
    last_line = Agent.get(context, & &1)
    {:ok, js} = Poison.decode(last_line)
    Logger.debug("Last line #{inspect(last_line)}")
    assert Map.get(js, "error") == "unknown_method"

    MOM.RPC.EndPoint.stop(ep1)
    MOM.RPC.EndPoint.JSON.stop(json)
    MOM.RPC.EndPoint.Caller.stop(caller)
  end

  test "As method caller" do
    {:ok, context} = Agent.start_link(fn -> nil end)
    {ep1, ep2} = MOM.RPC.EndPoint.pair()
    MOM.RPC.EndPoint.tap(ep1)

    {:ok, json} =
      MOM.RPC.EndPoint.JSON.start_link(ep1, {__MODULE__, :writef_last_line, [context]})

    {:ok, mc} = MOM.RPC.EndPoint.MethodCaller.start_link(ep2)

    MOM.RPC.EndPoint.MethodCaller.add_method(mc, "echo", fn x -> x end)

    {:ok, jsline} = Poison.encode(%{method: "echo", params: [1, 2, 3], id: 1})
    assert MOM.RPC.EndPoint.JSON.parse_line(json, jsline) == :ok
    :timer.sleep(200)
    last_line = Agent.get(context, & &1)
    {:ok, js} = Poison.decode(last_line)
    assert Map.get(js, "result") == [1, 2, 3]

    MOM.RPC.EndPoint.stop(ep1)
    MOM.RPC.EndPoint.JSON.stop(json)
    MOM.RPC.EndPoint.Caller.stop(mc)
  end

  test "Client calls a long running method on server method caller" do
    {:ok, context} = Agent.start_link(fn -> nil end)
    {ep1, ep2} = MOM.RPC.EndPoint.pair()
    MOM.RPC.EndPoint.tap(ep1)

    {:ok, json} =
      MOM.RPC.EndPoint.JSON.start_link(ep1, {__MODULE__, :writef_last_line, [context]})

    {:ok, mc} = MOM.RPC.EndPoint.MethodCaller.start_link(ep2)

    MOM.RPC.EndPoint.MethodCaller.add_method(mc, "sleep", fn _msg ->
      # 7s, 5s is the default timeout, 6 on the limit to detect it. 7 always detects it
      :timer.sleep(7000)
      {:ok, :ok}
    end)

    # call a long runing function on server
    {:ok, jsline} = Poison.encode(%{method: "sleep", params: [], id: 1})
    assert MOM.RPC.EndPoint.JSON.parse_line(json, jsline) == :ok

    # should patiently wait
    for _i <- 1..8 do
      :timer.sleep(1_000)
      last_line = Agent.get(context, & &1)

      case last_line do
        nil ->
          true

        last_line ->
          # Logger.debug(last_line)
          {:ok, js} = Poison.decode(last_line)
          assert Map.get(js, "error", false) == false
          true
      end
    end

    last_line = Agent.get(context, & &1)
    {:ok, js} = Poison.decode(last_line)
    # Logger.debug(inspect js)
    assert Map.get(js, "result") == "ok"
  end

  test "No process leaking" do
    # settle process destruction if needed.
    :timer.sleep(30)
    pre_proc = :erlang.processes()
    pre_count = Enum.count(pre_proc)

    {:ok, client} = MOM.RPC.Client.start_link(writef: {__MODULE__, :writef_last_line, []})

    MOM.RPC.Client.add_method(client, "echo", & &1)
    # :timer.sleep(300) # settle time?

    mid_proc = :erlang.processes()
    mid_count = Enum.count(mid_proc)

    MOM.RPC.Client.stop(client)
    # :timer.sleep(300)

    post_proc = :erlang.processes()
    post_count = Enum.count(post_proc)

    rem_proc = post_proc -- pre_proc

    Logger.info("Pre #{pre_count}, mid #{mid_count}, post_count #{post_count}")
    Logger.info("Still running: #{inspect(rem_proc)}")

    for p <- rem_proc do
      Logger.info(
        "#{inspect(p)}: #{inspect(Process.info(p)[:registered_name])} #{
          inspect(Process.info(p)[:dictionary][:"$initial_call"], pretty: true)
        }"
      )
    end

    assert pre_count == post_count, "Some processes were leaked"
  end

  def writef_client_last_line(client, line) do
    Logger.debug("Read>> #{line}")
    MOM.RPC.Client.set(client, :last_line, line)
  end

  @tag timeout: 10_000
  test "Use Client" do
    {:ok, client} = MOM.RPC.Client.start_link(writef: {__MODULE__, :writef_client_last_line, []})

    # calls go and are answered by JSON
    task =
      Task.async(fn ->
        MOM.RPC.Client.call(client, "dir", [])
      end)

    :timer.sleep(20)
    last_line = MOM.RPC.Client.get(client, :last_line)
    Logger.debug("#{inspect(last_line)}")
    {:ok, js} = Poison.decode(last_line)
    assert js["method"] == "dir"
    assert js["params"] == []

    {:ok, jsres} =
      Poison.encode(%{
        id: js["id"],
        result: ["dir"]
      })

    MOM.RPC.Client.parse_line(client, jsres)
    res = Task.await(task)
    assert res == {:ok, ["dir"]}

    # Calls from JSON go to method caller
    MOM.RPC.Client.add_method(client, "hello", fn [arg1] ->
      "Hello #{arg1}!"
    end)

    {:ok, jsreq} =
      Poison.encode(%{
        id: 111,
        method: "hello",
        params: ["world"]
      })

    MOM.RPC.Client.parse_line(client, jsreq)
    :timer.sleep(20)
    last_line = MOM.RPC.Client.get(client, :last_line)
    Logger.debug("#{inspect(last_line)}")
    {:ok, js} = Poison.decode(last_line)
    assert js["id"] == 111
    assert js["result"] == "Hello world!"
  end

  def writef_benckmark_caller_json(client, line) do
    {:ok, js} = Poison.decode(line)

    {:ok, res} =
      Poison.encode(%{
        id: js["id"],
        result: js["params"]
      })

    MOM.RPC.Client.parse_line(client, res)
  end

  test "Benchmark Caller -> JSON" do
    {:ok, client} =
      MOM.RPC.Client.start_link(writef: {__MODULE__, :writef_benckmark_caller_json, []})

    ncalls = 10_000

    {_res, time} =
      MOM.Test.benchmark(fn ->
        Enum.reduce(0..ncalls, nil, fn _acc, _v ->
          assert MOM.RPC.Client.call(client, "echo", ["echo"]) == {:ok, ["echo"]}
        end)
      end)

    IO.puts("Caller -> RPC #{ncalls} calls in #{time}s | #{ncalls / time} calls/s")
    MOM.RPC.Client.stop(client)
  end

  def writef_benchmark_json_mc(context, ncalls, task, _client, line) do
    {:ok, js} = Poison.decode(line)
    assert js["result"] == ["echo"]
    n = Agent.get_and_update(context, &{&1 + 1, &1 + 1})

    if n == ncalls do
      send(task.pid, :ok)
    end
  end

  test "Benchmark JSON -> MethodCaller" do
    {:ok, context} = Agent.start_link(fn -> 0 end)

    task =
      Task.async(fn ->
        receive do
          _ -> :ok
        end
      end)

    ncalls = 100_000

    {:ok, client} =
      MOM.RPC.Client.start_link(
        writef: {__MODULE__, :writef_benchmark_json_mc, [context, ncalls, task]}
      )

    MOM.RPC.Client.add_method(client, "echo", & &1)

    {_res, time} =
      MOM.Test.benchmark(fn ->
        Enum.reduce(0..ncalls, nil, fn _acc, n ->
          {:ok, line} =
            Poison.encode(%{
              id: n,
              method: "echo",
              params: ["echo"]
            })

          assert MOM.RPC.Client.parse_line(client, line)
        end)

        Task.await(task)
      end)

    IO.puts("RPC -> MethodCaller #{ncalls} calls in #{time}s | #{ncalls / time} calls/s")
    MOM.RPC.Client.stop(client)
  end

  def writef_context_holders(client, line) do
    Logger.debug("Got line #{inspect(client)}, #{inspect(line)}")
    MOM.RPC.Client.set(client, :last_line, line)
    {:ok, js} = Poison.decode(line)

    if js["method"] != nil and js["id"] != nil do
      Logger.debug("Answer #{inspect(js)}")

      {:ok, jsres} =
        Poison.encode(%{id: js["id"], result: MOM.RPC.Client.get(client, js["params"])})

      MOM.RPC.Client.parse_line(client, jsres)
    end
  end

  @tag timeout: 1000
  test "Clients are the context holders" do
    {:ok, client} = MOM.RPC.Client.start_link(writef: {__MODULE__, :writef_context_holders, []})
    MOM.RPC.Client.tap(client)

    # no data yet
    res = MOM.RPC.Client.call(client, "get", "test")
    assert res == {:ok, nil}

    # set data, just get it
    MOM.RPC.Client.set(client, "test", "test")
    res = MOM.RPC.Client.call(client, "get", "test")
    assert res == {:ok, "test"}

    MOM.RPC.Client.set(client, "test", "gocha")

    MOM.RPC.Client.add_method(
      client,
      "test",
      fn ["get", what], context ->
        MOM.RPC.Client.get(context, what)
      end,
      context: true
    )

    {:ok, jsreq} =
      Poison.encode(%{
        id: 1,
        method: "test",
        params: ["get", "test"]
      })

    MOM.RPC.Client.parse_line(client, jsreq)
    :timer.sleep(30)
    last_line = MOM.RPC.Client.get(client, :last_line)
    Logger.debug("Last line #{inspect(last_line)}")
    {:ok, jsres} = Poison.decode(last_line)
    assert jsres["result"] == "gocha"
  end

  def test_with_guards(args, context) do
    Logger.debug("Called test with context #{inspect(context)}")
    MOM.RPC.Client.update(context, :called, fn n -> n + 1 end)
    args
  end

  def guard_perms(context, options) do
    Logger.debug("Check guard for #{inspect(context)} / #{inspect(options[:perms])}")

    # ensure all perms in required are in context
    myperms = MOM.RPC.Client.get(context, :perms)

    allow =
      if myperms do
        Enum.all?(options[:perms], fn p ->
          Enum.member?(myperms, p)
        end)
      else
        false
      end

    if allow do
      true
    else
      :permission_denied
    end
  end

  test "RPC Calls on client with guards" do
    {:ok, client} = MOM.RPC.Client.start_link(writef: {__MODULE__, :writef_client_last_line, []})

    MOM.RPC.Client.add_guard(client, {__MODULE__, :guard_perms, []})

    MOM.RPC.Client.add_method(client, "test", {__MODULE__, :test_with_guards, []},
      perms: ["a", "b"],
      context: true
    )

    {:ok, jsreq} =
      Poison.encode(%{
        id: 1,
        method: "test",
        params: ["test"]
      })

    MOM.RPC.Client.set(client, :called, 0)
    called = MOM.RPC.Client.get(client, :called)
    assert called == 0

    res = MOM.RPC.Client.parse_line(client, jsreq)
    :timer.sleep(30)
    Logger.debug("test -> #{inspect(res)}")
    last_line = MOM.RPC.Client.get(client, :last_line)
    Logger.debug("Last line #{inspect(last_line)}")
    called = MOM.RPC.Client.get(client, :called)
    assert called == 0

    MOM.RPC.Client.set(client, :perms, ["a", "b", "c"])
    res = MOM.RPC.Client.parse_line(client, jsreq)
    :timer.sleep(30)
    Logger.debug("test -> #{inspect(res)}")
    last_line = MOM.RPC.Client.get(client, :last_line)
    Logger.debug("Last line #{inspect(last_line)}")
    called = MOM.RPC.Client.get(client, :called)
    assert called == 1

    MOM.RPC.Client.set(client, :perms, ["a", "c"])
    res = MOM.RPC.Client.parse_line(client, jsreq)
    :timer.sleep(30)
    Logger.debug("test -> #{inspect(res)}")
    last_line = MOM.RPC.Client.get(client, :last_line)
    Logger.debug("Last line #{inspect(last_line)}")
    called = MOM.RPC.Client.get(client, :called)
    assert called == 1
  end

  def writef_echo(client, line) do
    {:ok, msg} = Poison.decode(line)

    case msg do
      %{"method" => "echo", "id" => id, "params" => params} ->
        {:ok, jsres} =
          Poison.encode(%{
            id: id,
            result: params
          })

        MOM.RPC.Client.parse_line(client, jsres)

      %{"method" => "error", "id" => id, "params" => params} ->
        {:ok, jsres} =
          Poison.encode(%{
            id: id,
            error: params
          })

        MOM.RPC.Client.parse_line(client, jsres)

      _ ->
        :ok
    end
  end

  @tag timeout: 1_000
  test "Basic JSON substitutions" do
    # Some substitutions on responses
    {:ok, client} = MOM.RPC.Client.start_link(writef: {__MODULE__, :writef_echo, []})

    res = MOM.RPC.Client.call(client, "echo", :ok)
    assert res == {:ok, :ok}

    res = MOM.RPC.Client.call(client, "error", :ok)
    assert res == {:error, "ok"}

    res = MOM.RPC.Client.call(client, "error", :unknown_method)
    assert res == {:error, :unknown_method}

    res = MOM.RPC.Client.call(client, "error", :timeout)
    assert res == {:error, :timeout}

    res = MOM.RPC.Client.call(client, "error", :exit)
    assert res == {:error, :exit}

    res = MOM.RPC.Client.call(client, "error", :exit2)
    assert res == {:error, "exit2"}
  end

  def writef_sleep_echo(client, line) do
    {:ok, msg} = Poison.decode(line)
    Logger.debug("#{inspect(self())}Got message #{to_string(line)}")

    case msg do
      %{"method" => "echo", "id" => id, "params" => [sleept, ret, pid]} ->
        :timer.sleep(sleept)
        MOM.RPC.Client.update(client, :count, fn count -> count + 1 end)

        if id do
          assert pid == inspect(self())

          {:ok, jsres} =
            Poison.encode(%{
              id: id,
              result: ret
            })

          MOM.RPC.Client.parse_line(client, jsres)
        end

      %{"result" => "ok"} ->
        n = MOM.RPC.Client.update(client, :count, fn count -> count + 1 end)
        Logger.debug("Solved #{n} calls")

      other ->
        Logger.debug("Got other #{inspect(other)}")
        :ok
    end
  end

  @tag timeout: 1_200
  test "Calls are not serialized" do
    # Can do several calls from the JSON side and they are answered as data is
    # ready, and viceversa

    {:ok, client} = MOM.RPC.Client.start_link(writef: {__MODULE__, :writef_sleep_echo, []})
    MOM.RPC.Client.set(client, :count, 0)

    # First call to other side. As call blocks, it needs to be called each on
    # one  process, which will be the same used to process the request.

    tasks =
      for _i <- 1..20 do
        Task.async(fn ->
          # Logger.debug("Ask as #{inspect(self())}")
          {:ok, :ok} = MOM.RPC.Client.call(client, "echo", [200, :ok, "#{inspect(self())}"])
        end)
      end

    for t <- tasks do
      Task.await(t)
    end

    assert MOM.RPC.Client.get(client, :count) == 20

    Logger.info("Now call events")
    # events are also non blocking and do not require the task trick to check.. careful here.
    for _i <- 1..20 do
      # Logger.debug("Ask as #{inspect(self())}")
      :ok = MOM.RPC.Client.event(client, "echo", [200, :ok, "#{inspect(self())}"])
    end

    # Now call from JSON to method caller.
    Logger.info("Now call to rpc")

    MOM.RPC.Client.add_method(client, "sleep", fn [sleept] ->
      :timer.sleep(sleept)
      :ok
    end)

    :timer.sleep(300)
    assert MOM.RPC.Client.get(client, :count) == 40

    for i <- 1..20 do
      {:ok, jsreq} =
        Poison.encode(%{
          id: i,
          method: "sleep",
          params: [200]
        })

      MOM.RPC.Client.parse_line(client, jsreq)
    end

    :timer.sleep(300)
    assert MOM.RPC.Client.get(client, :count) == 60
  end
end
