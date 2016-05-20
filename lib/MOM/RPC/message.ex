defmodule MOM.RPC.Message do
	@moduledoc ~S"""
	RPC Message, normally used as a MOM.Message payload.

	It has:

	* `method` -- Method to call on the other end
	* `params` -- List or map of parameters
	* `context` -- `MOM.RPC.Context` object with client context, as user or
	  permissions. Defined by client.
	"""
	defstruct [
		method: nil,
		params: nil,
		context: nil # context at calling client
	]
end
