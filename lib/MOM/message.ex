defmodule MOM.Message do
  @moduledoc ~S"""
  Main Message struct as send through channels.

  It has:

  * `id` -- An unique identifier, only used if requires to associate requests and responses
  * `payload` -- Data send through the channels
  * `reply_to` -- If requires reply, a channel to which reply should be written
  * `error` -- If there is any error processing the message, this field is set,
    and the message sent to :deadleatter or :invalid channel.
  """
  defstruct [
    id: nil,
    payload: nil,
    reply_to: nil,
    error: nil,
  ]
end
