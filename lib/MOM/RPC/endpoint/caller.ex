require Logger

defmodule MOM.RPC.EndPoint.Caller do
  @moduledoc ~S"""
  A method caller to be able to call from code to other endpoints.

  This method caller can not receive requests.

  Ast first it tried to avoid all copy of messages, but then there was a
  deadlock; as it is the same pid that requests, and then waits for the answer,
  this wait can not succeed.

  `call -> req -> channel -> ... -> channel -> res (where do I put it) -> tell
  call req  is ready.`

  If the res has to be stored somewhere, why not the caller process? On top,
  normally the response is ready before call is waiting to waiting for the
  response, so it needs wait/store response (wait if data is not ready, setit
  apart if it is)

  """
  use GenServer

  def start_link(endpoint, options \\ []) do
    {:ok, pid} = GenServer.start_link(__MODULE__, endpoint, options)

    MOM.RPC.EndPoint.update_in(endpoint, fn
      # No requests possible to caller
      %MOM.RPC.Request{id: id} when not is_nil(id) ->
        {:error, :unknown_method}
      %MOM.RPC.Request{} ->
        {:error, :unknown_method}

      # Only responses
      %MOM.RPC.Response{id: id, result: result} ->
        # Logger.debug("got response #{inspect id} #{inspect result}")
        GenServer.cast(pid, {:set_answer, id, {:ok, result}})
      %MOM.RPC.Response.Error{id: id, error: error} ->
        GenServer.cast(pid, {:set_answer, id, {:error, error}})
      end, monitor: pid)

    {:ok, pid}
  end

  def stop(caller, reason \\ :normal) do
    GenServer.stop(caller, reason)
  end

  def call(client, method, params, timeout \\ 60_000) when is_number(timeout) do
    {id, in_, out} = GenServer.call(client, {:get_next_id_and_inout})
    msg = %MOM.RPC.Request{ id: id, method: method, params: params, context: nil, reply: in_ }
    # Logger.debug("Send message #{inspect out} #{inspect msg, pretty: true}")
    MOM.Channel.send(out, msg)
    GenServer.call(client, {:get_answer, id}, timeout)
  end

  def event(client, method, params) do
    out = GenServer.call(client, {:get_out})
    MOM.Channel.send(out, %MOM.RPC.Request{
      id: nil, method: method, params: params, context: nil
    })
  end

  # server impl
  def init(%{out: out, in: in_}) do
    {:ok, %{
      out: out,
      in: in_,
      maxid: 1,
      wait_answer: %{},
      answers: %{},
    }}
  end

  def handle_call({:get_next_id_and_inout}, _from, status) do
    {:reply, {status.maxid, status.in, status.out}, %{ status |
      maxid: status.maxid + 1,
    }}
  end
  def handle_call({:get_out}, _from, status) do
    {:reply, status.out, status}
  end

  def handle_call({:get_answer, id}, from, status) do
    # Logger.debug("Wait for #{inspect id}")
    case Map.pop(status.answers, id) do
      {nil, _answers} ->
        # Logger.debug("Answer not ready, wait.")
        {:noreply, %{ status |
          wait_answer: Map.put(status.wait_answer, id, from)
        }}
      {from, answers} ->
        # Logger.debug("Answer READY, answer to #{inspect from}")
        {:reply, from, %{ status |
          answers: answers
        }}
    end
  end

  def handle_cast({:set_answer, id, answer}, status) do
    # Logger.debug("Got for #{inspect id}")
    {waiter, wait_answer} = Map.pop(status.wait_answer, id)

    status = case waiter do
      nil ->
        # Logger.debug("Ok, not really waiting, I received before time. I store who to answer to #{inspect id}.")
        %{ status |
          answers: Map.put(status.answers, id, answer),
        }
      waiter ->
        GenServer.reply(waiter, answer)
        %{ status |
          wait_answer: wait_answer
        }
    end

    {:noreply, status}
  end
end
