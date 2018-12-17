defmodule MOM.RPC.Request do
	defstruct [
		id: nil,
		method: nil,
		params: nil,
		context: nil # context at calling client
	]
end
