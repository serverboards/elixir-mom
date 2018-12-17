require Logger
defmodule Serverboards.RPC.ClientTest do
  use ExUnit.Case
  @moduletag :capture_log

  test "Bad protocol" do
    {ep1, ep2} = MOM.RPC.EndPoint.pair()
    {:ok, json} = MOM.RPC.EndPoint.JSON.start_link(ep1, nil)
    {:ok, _mc} = MOM.RPC.EndPoint.MethodCaller.start_link(ep2)

    {:error, :bad_protocol} = MOM.RPC.EndPoint.JSON.parse_line json, "bad protocol"

    # Now a good call
    {:ok, mcjson} = Poison.encode(%{method: "dir", params: [], id: 1})
    :ok = MOM.RPC.EndPoint.JSON.parse_line json, mcjson

    MOM.RPC.EndPoint.stop(ep1)
  end

  test "Good protocol" do
    {:ok, context} = Agent.start_link(fn -> nil end)
    {ep1, ep2} = MOM.RPC.EndPoint.pair()
    {:ok, json} = MOM.RPC.EndPoint.JSON.start_link(ep1, fn line ->
      Agent.update(context, fn _ -> line end)
    end)
    {:ok, _mcall} = MOM.RPC.EndPoint.MethodCaller.start_link(ep2)
    MOM.RPC.EndPoint.tap(ep1)


    {:ok, mc} = Poison.encode(%{method: "dir", params: [], id: 1})
    MOM.RPC.EndPoint.JSON.parse_line json, mc, context

    :timer.sleep(200)

    {:ok, json} = Poison.decode( Agent.get(context, &(&1)) )
    Logger.debug(inspect json)
    assert Map.get(json,"result") == ~w(dir)

    MOM.RPC.EndPoint.stop(ep1)
    Agent.stop(context)
  end

  test "Call to client" do
    {:ok, context} = Agent.start_link(fn -> nil end)
    {:ok, called} = Agent.start_link(fn -> false end)
    {ep1, ep2} = MOM.RPC.EndPoint.pair()
    MOM.RPC.EndPoint.tap(ep1)
    {:ok, json} = MOM.RPC.EndPoint.JSON.start_link(ep1, fn line ->
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
    :timer.sleep(20) #20 ms

    # manual reply
    assert Agent.get(called, &(&1)) == false
    last_line = Agent.get(context, &(&1))
    Logger.debug("Last line #{inspect last_line}")
    {:ok, js} = Poison.decode(last_line)
    assert Map.get(js, "method") == "dir"
    {:ok, res} = Poison.encode(%{ id: 1, result: []})
    Logger.debug("Writing>> #{res}")
    assert (MOM.RPC.EndPoint.JSON.parse_line json, res) == :ok

    :timer.sleep(20) # 20ms

    assert Agent.get(called, &(&1)) == true

    MOM.RPC.EndPoint.Caller.event caller, "auth", ["basic"]
    :timer.sleep(1)
    last_line = Agent.get(context, &(&1))
    {:ok, js} = Poison.decode(last_line)
    assert Map.get(js,"method") == "auth"
    assert Map.get(js,"params") == ["basic"]
    assert Map.get(js,"id") == nil

    MOM.RPC.EndPoint.stop(ep1)
    MOM.RPC.EndPoint.JSON.stop(json)
    MOM.RPC.EndPoint.Caller.stop(caller)
  end

  test "Call from client" do
    {:ok, context} = Agent.start_link(fn -> nil end)
    {ep1, ep2} = MOM.RPC.EndPoint.pair()
    {:ok, json} = MOM.RPC.EndPoint.JSON.start_link(ep1, fn line ->
      Agent.update(context, fn _ -> line end)
    end)
    {:ok, _caller} = MOM.RPC.EndPoint.Caller.start_link(ep2)
    MOM.RPC.EndPoint.tap(ep1)

    # events, have no reply never
    {:ok, jsline} = Poison.encode(%{ method: "ready", params: [] })
    assert (MOM.RPC.EndPoint.JSON.parse_line json, jsline) == :ok
    :timer.sleep(200)
    last_line = Agent.get(context, &(&1))
    assert last_line == nil

    # method calls, have it, for example, unknown
    {:ok, jsline} = Poison.encode(%{ method: "ready", params: [], id: 1})
    assert (MOM.RPC.EndPoint.JSON.parse_line json, jsline) == :ok
    :timer.sleep(200)
    last_line = Agent.get(context, &(&1))
    {:ok, js} = Poison.decode(last_line)
    assert Map.get(js,"error") == "unknown_method"

    MOM.RPC.EndPoint.stop(ep1)
  end

  test "As method caller" do
    {:ok, client} = Client.start_link writef: :context

    Client.add_method client, "echo", fn x -> x end
    Client.add_method_caller client, fn msg -> msg.payload.params end


    {:ok, json} = Poison.encode(%{ method: "echo", params: [1,2,3], id: 1 })
    assert (Client.parse_line client, json) == :ok
    :timer.sleep(200)
    {:ok, js} = Poison.decode(Client.get client, :last_line)
    assert Map.get(js,"result") == [1,2,3]

    Client.stop(client)
  end

  test "Client calls a long running method on server method caller" do
    {:ok, client} = Client.start_link writef: :context

    Client.add_method_caller client, fn _msg ->
      :timer.sleep(7000) # 7s, 5s is the default timeout, 6 on the limit to detect it. 7 always detects it
      {:ok, :ok}
    end

    # call a long runing function on server
    {:ok, json} = Poison.encode(%{ method: "sleep", params: [], id: 1 })
    assert (Client.parse_line client, json) == :ok

    # should patiently wait
    for _i <- 1..8 do
      :timer.sleep(1_000)
      case (Client.get client, :last_line) do
        nil ->
          true
        last_line ->
          #Logger.debug(last_line)
          {:ok, js} = Poison.decode(last_line)
          assert Map.get(js, "error", false) == false
          true
      end
    end
    {:ok, js} = Poison.decode(Client.get client, :last_line)
    #Logger.debug(inspect js)
    assert Map.get(js,"result") == "ok"

    Client.stop(client)
  end

  test "No process leaking" do
    pre_proc = :erlang.processes()
    pre_count = Enum.count(pre_proc)

    {:ok, client} = Client.start_link writef: :context

    Client.add_method client, "echo", &(&1)
    # :timer.sleep(300) # settle time?

    mid_proc = :erlang.processes()
    mid_count = Enum.count(mid_proc)

    Client.stop(client)
    # :timer.sleep(300)

    post_proc = :erlang.processes()
    post_count = Enum.count(post_proc)

    rem_proc = post_proc -- pre_proc

    Logger.info("Pre #{pre_count}, mid #{mid_count}, post_count #{post_count}")
    Logger.info("Still running: #{inspect rem_proc}")
    for p <- rem_proc do
      Logger.info("#{inspect p}: #{inspect (Process.info(p)[:registered_name])} #{inspect (Process.info(p)[:dictionary][:"$initial_call"]), pretty: true}")
    end

    assert pre_count == post_count, "Some processes were leaked"
  end
end
