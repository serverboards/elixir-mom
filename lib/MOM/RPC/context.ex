defmodule MOM.RPC.Context do
  @moduledoc ~S"""
  Stateful map.

  It creates a process with a map to ease context storage and management.

  Example:

```
  iex> {:ok, ma} = start_link()
  iex> set ma, "test", true
  :ok
  iex> get ma, "test"
  true
  iex> get ma, "does-not-exist"
  nil
  iex> delete ma, "test"
  :ok
  iex> get ma, "test"
  nil
  iex> stop ma
  :ok

```

  There is also some default value if MapAgent is nil, to allow some situations.

```
  iex> get nil, :test, :default_value
  :default_value

```

```
  iex> set nil, :failure, :nok
  ** (ArgumentError) Invalid context

```

  """

  def start_link(options \\ []) do
    Agent.start_link fn -> %{} end, options
  end

  def stop(ma, reason \\ :normal) do
    Agent.stop(ma, reason)
  end

  def debug(pid) do
    Agent.get pid, &(Map.keys &1)
  end

  @doc ~S"""
  Puts a value into the MapAgent.

  In oposittion to get, if user tries to put it will fail (Agent fail actually)
  """
  def set(ma, k, v) do
    if not is_pid(ma) do
      raise ArgumentError, "Invalid context"
    else
      Agent.update ma, &Map.put(&1, k, v)
    end
  end

  @doc ~S"""
  Returns the statefull value of k, or d as default

  Allows to get from a nil MapAgent the default value, so methods can be used on both context clients and contextless.
  """
  def get(ma, k, d \\ nil) do
    if ma == nil do
      d
    else
      Agent.get ma, &Map.get(&1, k, d)
    end
  end

  def delete(ma, k) do
    Agent.update ma, &Map.delete(&1, k)
  end

  @doc ~S"""
  Allows to update atomically a map into the context

  Example:

```
  iex> {:ok, c} = start_link()
  iex> update c, :test, a: 1
  iex> get c, :test
  %{ a: 1 }
  iex> update c, :test, [a: nil]
  iex> get c, :test
  %{}
  iex> update c, :test, [a: 1, b: 2, c: nil]
  iex> get c, :test
  %{ a: 1, b: 2 }

```

  Also can bu strings

```
  iex> {:ok, c} = start_link()
  iex> update c, :test, [{"string", 1}]
  iex> get c, :test
  %{ "string" => 1 }

```

  """
  def update(ctx, k, map) do
    Agent.update ctx, fn st ->
      oldv=Map.get(st, k, %{})
      v=Enum.reduce(map, oldv, fn ({nk, nv}, acc) ->
        if nv == nil do
          Map.delete(acc, nk)
        else
          Map.put(acc, nk, nv)
        end
      end)
      Map.put(st, k, v)
    end
  end
end
