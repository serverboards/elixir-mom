defmodule MOM.RPC.Response do
  defmodule Error do
    defstruct id: nil,
              error: nil
  end

  defstruct id: nil,
            result: nil

  def from_tuple({:ok, result}, id) do
    %MOM.RPC.Response{
      id: id,
      result: result
    }
  end

  def from_tuple({:error, error}, id) do
    %MOM.RPC.Response.Error{
      id: id,
      error: error
    }
  end
end
