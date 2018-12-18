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

  test "Good protocol" do
    {:ok, context} = Agent.start_link(fn -> nil end)
    {ep1, ep2} = MOM.RPC.EndPoint.pair()

    {:ok, json} =
      MOM.RPC.EndPoint.JSON.start_link(ep1, fn line ->
        Agent.update(context, fn _ -> line end)
      end)

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
      MOM.RPC.EndPoint.JSON.start_link(ep1, fn line ->
        Logger.debug("Read>> #{line}")
        Agent.update(context, fn _ -> line end)
      end)

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
      MOM.RPC.EndPoint.JSON.start_link(ep1, fn line ->
        Agent.update(context, fn _ -> line end)
      end)

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
      MOM.RPC.EndPoint.JSON.start_link(ep1, fn line ->
        Logger.debug("Read>> #{line}")
        Agent.update(context, fn _ -> line end)
      end)

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
      MOM.RPC.EndPoint.JSON.start_link(ep1, fn line ->
        Logger.debug("Read>> #{line}")
        Agent.update(context, fn _ -> line end)
      end)

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
    pre_proc = :erlang.processes()
    pre_count = Enum.count(pre_proc)

    {:ok, context} = Agent.start_link(fn -> nil end)
    {ep1, ep2} = MOM.RPC.EndPoint.pair()
    MOM.RPC.EndPoint.tap(ep1)

    {:ok, json} =
      MOM.RPC.EndPoint.JSON.start_link(ep1, fn line ->
        Logger.debug("Read>> #{line}")
        Agent.update(context, fn _ -> line end)
      end)

    {:ok, mc} = MOM.RPC.EndPoint.MethodCaller.start_link(ep2)

    MOM.RPC.EndPoint.MethodCaller.add_method(mc, "echo", & &1)
    # :timer.sleep(300) # settle time?

    mid_proc = :erlang.processes()
    mid_count = Enum.count(mid_proc)

    MOM.RPC.EndPoint.stop(ep1)
    MOM.RPC.EndPoint.MethodCaller.stop(mc)
    MOM.RPC.EndPoint.JSON.stop(json)
    Agent.stop(context)
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

  @tag timeout: 10_000
  test "Use Client" do
    {:ok, context} = Agent.start_link(fn -> nil end)

    {:ok, client} =
      MOM.RPC.Client.start_link(
        writef: fn line ->
          Logger.debug("Read>> #{line}")
          Agent.update(context, fn _ -> line end)
        end
      )

    # calls go and are answered by JSON
    task =
      Task.async(fn ->
        MOM.RPC.Client.call(client, "dir", [])
      end)

    :timer.sleep(20)
    last_line = Agent.get(context, & &1)
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
    last_line = Agent.get(context, & &1)
    Logger.debug("#{inspect(last_line)}")
    {:ok, js} = Poison.decode(last_line)
    assert js["id"] == 111
    assert js["result"] == "Hello world!"
  end

  test "Benchmark Caller -> JSON" do
    {:ok, context} = Agent.start_link(fn -> nil end)

    {:ok, client} =
      MOM.RPC.Client.start_link(
        writef: fn line ->
          {:ok, js} = Poison.decode(line)

          {:ok, res} =
            Poison.encode(%{
              id: js["id"],
              result: js["params"]
            })

          client = Agent.get(context, & &1)
          MOM.RPC.Client.parse_line(client, res)
        end
      )

    Agent.update(context, fn _ -> client end)

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
        writef: fn line ->
          {:ok, js} = Poison.decode(line)
          assert js["result"] == ["echo"]
          n = Agent.get_and_update(context, &{&1 + 1, &1 + 1})

          if n == ncalls do
            send(task.pid, :ok)
          end

          :stop
        end
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
end
