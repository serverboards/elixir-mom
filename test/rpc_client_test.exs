require Logger
defmodule Serverboards.RPC.ClientTest do
  use ExUnit.Case
  @moduletag :capture_log
  doctest MOM.RPC.Client, import: true

  alias MOM.RPC.Client

  test "Create and stop a client" do
    {:ok, client} = Client.start_link writef: :context

    Client.stop client

    # There is no easy test, its
    # a set of processes. Maybe FIXME as one dummy process parent of all the others
    #assert (Process.alive? client) == false
  end

  test "Bad protocol" do
    {:ok, client} = Client.start_link writef: :context

    {:error, :bad_protocol} = Client.parse_line client, "bad protocol"

    # Now a good call
    {:ok, mc} = Poison.encode(%{method: "dir", params: [], id: 1})
    :ok = Client.parse_line client, mc

    Client.stop(client)
  end

  test "Good protocol" do
    {:ok, client} = Client.start_link writef: :context

    {:ok, mc} = Poison.encode(%{method: "dir", params: [], id: 1})
    Client.parse_line client, mc

    :timer.sleep(200)

    {:ok, json} = Poison.decode( Client.get client, :last_line )
    assert Map.get(json,"result") == ~w(dir ping version)

    Client.stop(client)
  end

  test "Call to client" do
    {:ok, client} = Client.start_link writef: :context

    MOM.RPC.Client.cast client, "dir", [], fn {:ok, []} ->
      Client.set client, :called, true
    end
    :timer.sleep(20)

    # manual reply
    assert (Client.get client, :called, false) == false
    {:ok, js} = Poison.decode(Client.get client, :last_line)
    assert Map.get(js,"method") == "dir"
    {:ok, res} = Poison.encode(%{ id: 1, result: []})
    Logger.debug("Writing result #{res}")
    assert (Client.parse_line client, res) == :ok

    :timer.sleep(20)

    assert (Client.get client, :called) == true


    Client.event client, "auth", ["basic"]
    :timer.sleep(20)
    {:ok, js} = Poison.decode(Client.get client, :last_line)
    assert Map.get(js,"method") == "auth"
    assert Map.get(js,"params") == ["basic"]
    assert Map.get(js,"id") == nil

    Client.stop(client)
  end

  test "Call from client" do
    {:ok, client} = Client.start_link writef: :context

    # events, have no reply never
    {:ok, json} = Poison.encode(%{ method: "ready", params: [] })
    assert (Client.parse_line client, json) == :ok
    :timer.sleep(20)
    assert (Client.get client, :last_line) == nil

    # method calls, have it, for example, unknown
    {:ok, json} = Poison.encode(%{ method: "ready", params: [], id: 1})
    assert (Client.parse_line client, json) == :ok
    :timer.sleep(200)
    {:ok, js} = Poison.decode(Client.get client, :last_line)
    assert Map.get(js,"error") == "unknown_method"

    Client.stop(client)
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
end
