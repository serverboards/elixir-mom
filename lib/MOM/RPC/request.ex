defmodule MOM.RPC.Request do
	defstruct [
		id: nil,
		method: nil,
		params: nil,
		reply: nil, # which channel to write the answer
		context: nil # context at calling client
	]
end
