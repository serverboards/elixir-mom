ExUnit.start()

defmodule MOM.Test do
  def benchmark(func) do
    tini = :erlang.timestamp()

    data = func.()

    tend = :erlang.timestamp()
    tdiff = :timer.now_diff(tend, tini) / 1_000_000.0
    {data, tdiff}
  end
end
