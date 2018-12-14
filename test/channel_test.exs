require Logger

defmodule MOMTest do
  use ExUnit.Case
  @moduletag :capture_log

  test "Simple channel" do
    {:ok, channel} = MOM.Channel.start_link()

    is_called = :ets.new(:is_called, [])

    MOM.Channel.subscribe(channel, fn _message ->
      :ets.insert(is_called, {:is_called, true})
      Logger.debug("Received message")
    end)

    MOM.Channel.send(channel, %{})

    assert :ets.lookup(is_called, :is_called) == [is_called: true]
  end


  test "Multiple subscribers" do
    {:ok, channel} = MOM.Channel.start_link()

    res = :ets.new(:res, [])
    :ets.insert(res, {:res, 0})

    {:ok, _first_id} = MOM.Channel.subscribe(channel, fn _message ->
      [res: n] = :ets.lookup(res, :res)
      :ets.insert(res, {:res, n+1})
    end)
    {:ok, second_id} = MOM.Channel.subscribe(channel, fn _message ->
      [res: n] = :ets.lookup(res, :res)
      :ets.insert(res, {:res, n*2})
    end)

    n = MOM.Channel.send(channel, %{})
    assert :ets.lookup(res, :res) == [res: 2]
    assert n == 2

    n = MOM.Channel.send(channel, %{})
    assert :ets.lookup(res, :res) == [res: 6]
    assert n == 2

    ## Now unsub the second
    resunsub = MOM.Channel.unsubscribe(channel, second_id)
    assert resunsub == true

    n = MOM.Channel.send(channel, %{})
    assert :ets.lookup(res, :res) == [res: 7]
    assert n == 1

    # retry, not unsub
    resunsub = MOM.Channel.unsubscribe(channel, second_id)
    assert resunsub == false
  end

end
