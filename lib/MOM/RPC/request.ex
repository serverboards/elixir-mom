defmodule MOM.RPC.Request do
  defstruct id: nil,
            method: nil,
            params: nil,
            # which channel to write the answer
            reply: nil,
            # context at calling client
            context: nil
end
