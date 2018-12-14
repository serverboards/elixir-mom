require Logger

defmodule MOMTest do
  use ExUnit.Case, async: true
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
    MOM.Channel.stop(channel)
  end

  test "Several channels at the same time" do
    {:ok, channel_a} = MOM.Channel.start_link()
    {:ok, channel_b} = MOM.Channel.start_link()

    res = :ets.new(:res, [])
    :ets.insert(res, {:res_a, 0})
    :ets.insert(res, {:res_b, 0})

    {:ok, _first_id} = MOM.Channel.subscribe(channel_a, fn _message ->
      [res_a: n] = :ets.lookup(res, :res_a)
      :ets.insert(res, {:res_a, n+1})
    end)
    {:ok, _first_id} = MOM.Channel.subscribe(channel_b, fn _message ->
      [res_b: n] = :ets.lookup(res, :res_b)
      :ets.insert(res, {:res_b, n+1})
    end)
    MOM.Channel.send(channel_a, %{})
    MOM.Channel.send(channel_a, %{})
    MOM.Channel.send(channel_a, %{})
    MOM.Channel.send(channel_a, %{})

    MOM.Channel.send(channel_b, %{})

    assert :ets.lookup(res, :res_a) == [res_a: 4]
    assert :ets.lookup(res, :res_b) == [res_b: 1]
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

    MOM.Channel.stop(channel)
  end

  test "Channel by name, not created" do
    res = :ets.new(:res, [])
    :ets.insert(res, {:res, 0})

    {:ok, _first_id} = MOM.Channel.subscribe(:test_channel_by_name, fn _message ->
      [res: n] = :ets.lookup(res, :res)
      :ets.insert(res, {:res, n+1})
    end)
    {:ok, second_id} = MOM.Channel.subscribe(:test_channel_by_name, fn _message ->
      [res: n] = :ets.lookup(res, :res)
      :ets.insert(res, {:res, n*2})
    end)

    n = MOM.Channel.send(:test_channel_by_name, %{})
    assert :ets.lookup(res, :res) == [res: 2]
    assert n == 2

    MOM.Channel.unsubscribe(:test_channel_by_name, second_id)
    n = MOM.Channel.send(:test_channel_by_name, %{})
    assert :ets.lookup(res, :res) == [res: 3]
    assert n == 1
  end

  test "Broadcast channel. It returns inmediately. Uses an internal task and will copy the message." do
    {:ok, channel} = MOM.Channel.Broadcast.start_link()
    selfpid = self()

    res = :ets.new(:res, [:public])
    :ets.insert(res, {:res, 0})

    {:ok, _first_id} = MOM.Channel.subscribe(channel, fn _message ->
      assert selfpid != self()
      :timer.sleep(200)
      [res: n] = :ets.lookup(res, :res)
      :ets.insert(res, {:res, n+1})
    end)
    {:ok, second_id} = MOM.Channel.subscribe(channel, fn _message ->
      assert selfpid != self()
      :timer.sleep(200)
      [res: n] = :ets.lookup(res, :res)
      :ets.insert(res, {:res, n*2})
    end)

    n = MOM.Channel.send(channel, %{})
    assert :ets.lookup(res, :res) == [res: 0]
    :timer.sleep(500)
    assert :ets.lookup(res, :res) == [res: 2]

    MOM.Channel.stop(channel)
  end


  test "Point To Point Channels stop on first that returns :stop. Else return :cont." do
    {:ok, channel} = MOM.Channel.PointToPoint.start_link()
    res = :ets.new(:res, [])
    :ets.insert(res, {:res, 0})

    {:ok, first_id} = MOM.Channel.subscribe(channel, fn _message ->
      [res: n] = :ets.lookup(res, :res)
      :ets.insert(res, {:res, n+1})
      :stop
    end)
    {:ok, second_id} = MOM.Channel.subscribe(channel, fn _message ->
      [res: n] = :ets.lookup(res, :res)
      :ets.insert(res, {:res, n * 20})
      :cont
    end)
    n = MOM.Channel.send(channel, %{})
    assert :ets.lookup(res, :res) == [res: 1]

    MOM.Channel.unsubscribe(channel, first_id)
    n = MOM.Channel.send(channel, %{})
    assert :ets.lookup(res, :res) == [res: 20]

    MOM.Channel.unsubscribe(channel, second_id)
    n = MOM.Channel.send(channel, %{})
    assert :ets.lookup(res, :res) == [res: 20]
  end

  test "Some subscriber is dead, remove it automatically (monitor)" do
    res = :ets.new(:res, [])
    :ets.insert(res, {:res, 0})

    Task.async(fn ->
      MOM.Channel.subscribe(:test_dead, fn message ->
        flunk "I should be dead and not receive messages"
      end)
    end)
    MOM.Channel.subscribe(:test_dead, fn message ->
      [res: n] = :ets.lookup(res, :res)
      :ets.insert(res, {:res, n+1})
    end)
    :timer.sleep(100)

    MOM.Channel.send(:test_dead, %{})
    assert :ets.lookup(res, :res) == [res: 1]
  end
end
