require Logger

defmodule MOM.RPC.EndPoint do
  @moduledoc ~S"""
  And endpoint receives calls and gives answers, and do calls and receive answers.

  It can be for example the stdin/stdout, where messages are written with JSON
  RPC, or a TCP connection, or a method caller, that only receives calls and
  gives answers.

  Endpoints have each an in and an out channel. When connecting two endpoints,
  it just connects outputs to inputs.
  """
  defstruct in: nil,
            out: nil

  use GenServer

  def new() do
    {:ok, in_} = MOM.Channel.PointToPoint.start_link(default: &MOM.RPC.EndPoint.unknown_method/2)
    {:ok, out} = MOM.Channel.PointToPoint.start_link(default: &MOM.RPC.EndPoint.unknown_method/2)

    %MOM.RPC.EndPoint{
      # Anything I receive: call request | answers
      in: in_,
      # Anything I send: call request | answers
      out: out
    }
  end

  def stop(ep, reason \\ :normal) do
    MOM.Channel.stop(ep.in, reason)
    MOM.Channel.stop(ep.out, reason)
  end

  @doc ~S"""
  Reverses the channels so that the input is the output of another endpoint
  """
  def reverse(endpoint) do
    %MOM.RPC.EndPoint{
      in: endpoint.out,
      out: endpoint.in
    }
  end

  @doc ~S"""
    Creates a pair of connected endpoints.

    Sets the out of each side to in of the other.

    Initial implementation dependant on endpoints creating one side, and then
    connecting, but hat would only be required if the endpoints could be N:M
    connected, but in rea lity is just one-to-one.

    Both status can be created with (pseudocode) `pair() + new_endpoint_type(a) +
    new_endpoint_type(b)` or `new() + new() + new_endpoint_type(a) +
    new_endpoint_type(b) + connect()`` The final result is the same.

    It is actually just a normal Endpoint, and its reverse

  """
  @spec pair() :: {%MOM.RPC.EndPoint{}, %MOM.RPC.EndPoint{}}
  def pair() do
    ep = new()

    {
      ep,
      reverse(ep)
    }
  end

  # @doc ~S"""
  # Creates three endpoints so that the middle one is connected to both sides
  #
  # And input to middle on is the same, and output goes to the third:
  #
  # ```
  # A | --> | B | --> | C
  # ```
  #
  # This is required by the client connection.
  #
  # Normally A could not get responses, but the messages carry a `reply` field
  # just for that.
  # """
  # def three() do
  #   {:ok, inA} = MOM.Channel.PointToPoint.start_link(default: &MOM.RPC.EndPoint.unknown_method/2)
  #   {:ok, inB} = MOM.Channel.PointToPoint.start_link(default: &MOM.RPC.EndPoint.unknown_method/2)
  #   {:ok, inC} = MOM.Channel.PointToPoint.start_link(default: &MOM.RPC.EndPoint.unknown_method/2)
  #
  #   {
  #     %MOM.RPC.EndPoint{
  #       in: inA,
  #       out: inB
  #     },
  #     %MOM.RPC.EndPoint{
  #       in: inB,
  #       out: inC
  #     },
  #     %MOM.RPC.EndPoint{
  #       in: inC,
  #       out: inB
  #     }
  #   }
  # end
  #
  @doc ~S"""
    Connects the two endpoints.
  """
  @spec connect(%MOM.RPC.EndPoint{}, %MOM.RPC.EndPoint{}) :: :ok
  def connect(a, b) do
    MOM.Channel.connect(a.out, b.in)
    MOM.Channel.connect(b.out, a.in)
    :ok
  end

  @doc ~S"""
  Simplify message managing at endpoints

  Each ndpoint has to manage the messages in a similar fashion: if it is a
  request, get the answer and give it back, if its a response, just write it.

  If it is a request, it can answer {:error, :unknown_method} method to allow
  the p2p channel chain to continue the evaluation. It can also return `:noreply
  which means that the reply will come from any other means.

  `
  """
  def update_in(endpoint, infunc, options \\ []) do
    MOM.Channel.subscribe(
      endpoint.in,
      fn
        %MOM.RPC.Request{} = msg ->
          mcres = infunc.(msg)
          # Logger.debug("infunc  #{inspect(infunc)} ( #{inspect(msg)} ) -> #{inspect(mcres)}")

          cont_or_stop =
            case mcres do
              {:error, :unknown_method} ->
                :cont

              :noreply ->
                :stop

              _ ->
                if msg.id do
                  msgout =
                    case mcres do
                      {:error, error} ->
                        %MOM.RPC.Response.Error{
                          id: msg.id,
                          error: error
                        }

                      {:ok, result} ->
                        %MOM.RPC.Response{
                          id: msg.id,
                          result: result
                        }

                      # Simple case answer. It is converted to {:ok, res}
                      other ->
                        %MOM.RPC.Response{
                          id: msg.id,
                          result: other
                        }
                    end

                  # Logger.debug("Send response #{inspect msgout}")
                  MOM.Channel.send(msg.reply, msgout)
                end

                :stop
            end

          # Logger.debug("Cont or stop? #{inspect cont_or_stop}")
          cont_or_stop

        msg ->
          # Logger.debug("Got response? #{inspect msg}")
          infunc.(msg)
          :stop
      end,
      options
    )

    endpoint
  end

  def unknown_method(message, _options) do
    # Logger.debug("Unknown method: #{inspect message} #{inspect options}")
    if message.id != nil do
      MOM.Channel.send(message.reply, %MOM.RPC.Response.Error{
        error: :unknown_method,
        id: message.id
      })
    end
  end

  def tap(endpoint, idA \\ "A", idB \\ "B") do
    MOM.Tap.tap(endpoint.in, "#{idA} -> #{idB}")
    MOM.Tap.tap(endpoint.out, "#{idB} -> #{idA}")
  end
end
