defmodule MOM.RPC.EndPoint do
  @moduledoc ~S"""
  And endpoint receives calls and gives answers, and do calls and receive answers.

  It can be for example the stdin/stdout, where messages are written with JSON
  RPC, or a TCP connection, or a method caller, that only receives calls and
  gives answers.

  Endpoints have each an in and an out channel. When connecting two endpoints,
  it just connects outputs to inputs.
  """
  defstruct [
    in: nil,
    out: nil
  ]


  use GenServer

  def new() do
    {:ok, in_} = MOM.Channel.PointToPoint.start_link()
    {:ok, out} = MOM.Channel.PointToPoint.start_link()
    %MOM.RPC.EndPoint{
      # Anything I receive: call request | answers
      in: in_,
      # Anything I send: call request | answers
      out: out,
    }
  end

  @spec connect(%MOM.RPC.EndPoint{}, %MOM.RPC.EndPoint{}) :: :ok
  def connect(a, b) do
    MOM.Channel.connect(a.in, b.out)
    MOM.Channel.connect(b.in, a.out)
    :ok
  end

  def update_in(endpoint, infunc, options \\ []) do
    MOM.Channel.subscribe(endpoint.in, fn %MOM.RPC.Request{} = msg ->
      mcres = infunc.(msg)
      cont_or_stop = case mcres do
        {:error, :unknown_method} -> :cont
        _ -> :stop
      end
      if msg.id do
        msgout = case mcres do
          {:error, error} ->
            %MOM.RPC.Response.Error{
              id: msg.id,
              error: error,
            }
          {:ok, result} ->
            %MOM.RPC.Response{
              id: msg.id,
              result: result,
            }
        end
        MOM.RPC.Channel.send(endpoint.out, msgout)
      end

      cont_or_stop
    end, options)
    endpoint
  end
end
