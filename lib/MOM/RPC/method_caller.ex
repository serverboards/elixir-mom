require Logger

defmodule MOM.RPC.MethodCaller do
  @moduledoc ~S"""
  This module stores methods to be called later.

  They are stored in an execute efficient way, and allow to have a list
  of methods to allow introspection (`dir` method).

  Can be connected with a RPC gateway with `add_method_caller`

  ## Example

```
  iex> alias MOM.RPC.MethodCaller
  iex> {:ok, mc} = MethodCaller.start_link()
  iex> MethodCaller.add_method mc, "ping", fn _ -> "pong" end, async: false
  iex> MethodCaller.call mc, "ping", [], nil
  {:ok, "pong"}
  iex> MethodCaller.call mc, "dir", [], nil
  {:ok, ["dir", "ping"]}

```

-- NEW

  Method caller is a tree of disct of things to call. When you ask (lookup) for
  a method it returns a {callable, options} that will do the call itself.

  Both can be combined with call.
  """
  use GenServer

  alias MOM.RPC

  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, [name: Keyword.get(options, :name, nil)], options)
  end

  def stop(pid, reason \\ :normal) do
    GenServer.stop(pid, reason)
  end

  @doc ~S"""
  Return list of funtions known by this method caller
  """
  def dir(pid, context) when is_pid(pid) do
    GenServer.call(pid, {:dir, context})
  end

  @doc ~S"""
  Adds a method to be called later.

  Method function must returns:

  * {:ok, v} -- Ok value
  * {:error, v} -- Error to return to client
  * v -- Ok value

  Options may be:

  * `async`, default true. Execute in another task, returns a promise.
  * `context`, the called function will be called with the client context. It is a MOM.RPC.Context

  ## Example

```
  iex> alias MOM.RPC.MethodCaller
  iex> {:ok, mc} = MethodCaller.start_link
  iex> MethodCaller.add_method mc, "test_ok", fn _ -> {:ok, :response_ok} end
  iex> MethodCaller.add_method mc, "test_error", fn _ -> {:error, :response_error} end
  iex> MethodCaller.add_method mc, "test_plain", fn _ -> :response_plain_ok end
  iex> MethodCaller.call mc, "test_ok", [], nil
  {:ok, :response_ok}
  iex> MethodCaller.call mc, "test_error", [], nil
  {:error, :response_error}
  iex> MethodCaller.call mc, "test_plain", [], nil
  {:ok, :response_plain_ok}

```
  """
  def add_method(pid, name, f, options \\ []) do
    GenServer.call(pid, {:add_method, name, f, options})
  end


  @doc ~S"""
  Method callers can be chained, so that if current does not resolve, try on another

  This another caller can be even shared between several method callers.

  Method callers are optimized callers, but a single function can be passed and
  it will be called with an %RPC.Message. If it returns {:ok, res} or
  {:error, error} its processed, :empty or :nok tries next callers.

  ## Example:

  I will create three method callers, so that a calls, and b too. Method can
  be shadowed at parent too.

```
  iex> alias MOM.RPC.{MethodCaller, Context}
  iex> {:ok, a} = MethodCaller.start_link
  iex> {:ok, b} = MethodCaller.start_link
  iex> {:ok, c} = MethodCaller.start_link
  iex> MethodCaller.add_method a, "a", fn _ -> :a end
  iex> MethodCaller.add_method b, "b", fn _ -> :b end
  iex> MethodCaller.add_method c, "c", fn _ -> :c end
  iex> MethodCaller.add_method c, "c_", fn _, context -> {:c, Context.get(context, :user, nil)} end, context: true
  iex> MethodCaller.add_method_caller a, c
  iex> MethodCaller.add_method_caller b, c
  iex> {:ok, context} = Context.start_link
  iex> Context.set context, :user, :me
  iex> MethodCaller.call a, "c", [], context
  {:ok, :c}
  iex> MethodCaller.call a, "c_", [], context
  {:ok, {:c, :me}}
  iex> MethodCaller.call b, "c", [], context
  {:ok, :c}
  iex> MethodCaller.call b, "c_", [], context
  {:ok, {:c, :me}}
  iex> MethodCaller.add_method a, "c", fn _ -> :shadow end
  iex> MethodCaller.call a, "c", [], context
  {:ok, :shadow}
  iex> MethodCaller.call b, "c", [], context
  {:ok, :c}
  iex> MethodCaller.call b, "d", [], context
  {:error, :unknown_method}

```

  Custom method caller that calls a function

```
  iex> alias MOM.RPC.MethodCaller
  iex> {:ok, mc} = MethodCaller.start_link
  iex> MethodCaller.add_method_caller(mc, fn msg ->
  ...>   case msg.method do
  ...>     "hello."<>ret -> {:ok, ret}
  ...>     _ -> :nok
  ...>   end
  ...> end)
  iex> MethodCaller.call mc, "hello.world", [], nil
  {:ok, "world"}
  iex> MethodCaller.call mc, "world.hello", [], nil
  {:error, :unknown_method}

```
  """
  def add_method_caller(pid, pid) do
    raise RuntimeError, "Cant add a method caller to itself."
  end
  def add_method_caller(pid, nmc) when is_pid(pid) and is_pid(nmc) do
    GenServer.call(pid, {:add_method_caller, nmc})
  end


  @doc ~S"""
  Adds a guard to the method caller

  This guards are called to ensure that a called method is allowed to be called.

  If the method call is not allowed, it will be skipped as if never added, and
  `dir` will not return it neither.

  Guards are functions that receive the RPC message and the options of the
  method, and return true or false to mark if they allow or not that method
  call. This way generic guards can be created.

  `name` is a debug name used to log what guard failed. Any error/exception on
  guards are interpreted as denial. Clause errors are not logged to ease
  creation of guards for specific pattern matches. Other errors are reraised.

  The very same `dir` that would be called with a method caller can have guards
  that prevent its call, but the dir implementation has to make sure to return
  only the approved methods.

  ## Example

  It creates a method and a guard.

```
  iex> require Logger
  iex> {:ok, mc} = start_link()
  iex> add_method mc, "echo", &(&1), require_perm: "echo"
  iex> add_method_caller mc, fn
  ...>   %{ method: "dir" } -> {:ok, ["echo_fn"]}
  ...>   %{ method: "echo_fn", params: params } -> {:ok, params}
  ...>   _ -> {:error, :unknown_method }
  ...> end
  iex> add_guard mc, "perms", fn %{ context: context }, options ->
  ...>   case Keyword.get(options, :require_perm) do
  ...>     nil -> true # no require perms, ok
  ...>     required_perm ->
  ...>       Enum.member? Map.get(context, :perms, []), required_perm
  ...>   end
  ...> end
  iex> call mc, "echo", [1,2,3], %{ } # no context
  {:error, :unknown_method}
  iex> call mc, "echo", [1,2,3], %{ perms: [] } # no perms
  {:error, :unknown_method}
  iex> call mc, "echo", [1,2,3], %{ perms: ["echo"] } # no perms
  {:ok, [1,2,3]}
  iex> call mc, "echo_fn", [1,2,3], %{ } # no context
  {:error, :unknown_method}
  iex> call mc, "echo_fn", [1,2,3], %{ perms: [] } # no perms
  {:error, :unknown_method}
  iex> call mc, "echo_fn", [1,2,3], %{ perms: ["echo"] } # no perms
  {:ok, [1,2,3]}
  iex> call mc, "dir", [], %{}
  {:ok, ["dir"]}
  iex> call mc, "dir", [], %{ perms: ["echo"] }
  {:ok, ["dir", "echo", "echo_fn"]}

```

  In this example a map is used as context. Normally it would be a RPC.Context.
  """
  def add_guard(pid, name, guard_f) when is_pid(pid) and is_function(guard_f) do
    GenServer.call(pid, {:add_guard, name, guard_f})
  end

  def lookup(pid, method) do
    GenServer.call(pid, {:lookup, method})
  end


  def call(mc, method, args, context) when is_pid(mc) do
    case lookup(mc, method) do
      nil ->
        {:error, :unknown_method}
      func_options ->
        call(func_options, args, context)
    end
  end

  def call({func, options}, args, context) do
    try do
      if options[:context] do
        func.(args, context)
      else
        func.(args)
      end
    rescue
      error ->
        {:error, error}
    end
  end


  # server impl

  def init([name: name]) do
    pid=self()
    name = if name do name else inspect(self()) end
    state = %{
      methods: %{
        "dir" => {
          fn _, context ->
            dir(pid, context)
          end,
          [context: true]
        }
      },
      mc: [],
      guards: [],
      name: name
    }

    {:ok, state}
  end


  def handle_call({:lookup, method}, _from, status) do
    func = case Map.get(status.methods, method) do
      nil ->
        Enum.find_value(status.mc, &(lookup(&1, method)))
      method ->
        method
    end

    {:reply, func, status}
  end

  def handle_call({:dir, context}, _from, st) do
    local = st.methods
      |> Enum.flat_map(fn {name, {_, options}} ->
          if check_guards(%MOM.RPC.Request{ method: name, context: context}, options, st.guards) do
            [name]
          else
            []
          end
        end)
    other = Enum.flat_map( st.mc, &(dir(&1, context)) )
    res = Enum.uniq Enum.sort( local ++ other )
    {:reply, {:ok, res}, st}
  end

  def handle_call({:add_method, name, f, options}, _from, status) do
    {:reply, :ok, %{ status |
      methods: Map.put(status.methods, name, {f, options})
    }}
  end
  def handle_call({:add_guard, name, guard_f}, _from, status) do
    {:reply, :ok, %{ status |
      guards: status.guards ++ [{name, guard_f}]
    }}
  end
  def handle_call({:add_method_caller, nmc}, _from, status) do
    {:reply, :ok, %{ status |
      mc: [nmc | status.mc]
    }}
  end

  # Checks all the guards, return false if any fails.
  defp check_guards(%MOM.RPC.Request{}, _, []), do: true
  defp check_guards(%MOM.RPC.Request{} = msg, options, [{gname, gf} | rest]) do
    try do
      if gf.(msg, options) do
        #Logger.debug("Guard #{inspect msg} #{inspect gname} allowed pass")
        check_guards(msg, options, rest)
      else
        #Logger.debug("Guard #{inspect msg} #{inspect gname} STOPPED pass")
        false
      end
    rescue
      FunctionClauseError ->
        #Logger.debug("Guard #{inspect msg} #{inspect gname} STOPPED pass (Function Clause Error)")
        false
      e ->
        Logger.error("Error checking method caller guard #{gname}: #{inspect e}\n#{Exception.format_stacktrace}")
        false
    end
  end
end
