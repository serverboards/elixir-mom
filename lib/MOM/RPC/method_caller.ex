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
  """
  use GenServer

  alias MOM.RPC

  def start_link(options \\ []) do
    {:ok, pid} = GenServer.start_link(__MODULE__, [name: Keyword.get(options, :name, nil)], options)

    {:ok, pid}
  end

  def stop(pid, reason \\ :normal) do
    GenServer.stop(pid, reason)
  end

  @doc ~S"""
  Shows debug info about this method caller
  """
  def debug(false) do
    false
  end
  def debug(pid) do
    GenServer.call(pid, {:debug})
  end

  @doc ~S"""
  Return list of funtions known by this method caller
  """
  def __dir(pid, context) when is_pid(pid) do
    GenServer.call(pid, {:dir, context})
  end
  def __dir(f, context) when is_function(f) do
    # this version accepts a function that is a method caller
    try do
      case f.(%RPC.Message{method: "dir", context: context}) do
        {:ok, l} when is_list(l) -> l
        _o ->
          Logger.error("dir dir not return list at #{inspect f}. Please fix.")
          []
      end
    rescue
      e ->
        Logger.error("dir not implemented at #{inspect f}. Please fix.\n#{inspect e}\n#{ Exception.format_stacktrace System.stacktrace }")
        []
    end
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
  def add_method_caller(pid, pid, _) do
    raise RuntimeError, "Cant add a method caller to itself."
  end
  def add_method_caller(pid, nmc, options) when is_pid(pid) do
    GenServer.call(pid, {:add_method_caller, nmc, options})
  end
  def add_method_caller(pid, nmc), do: add_method_caller(pid, nmc, [])


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
  ...> end, require_perm: "echo"
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

  @doc ~S"""
  Calls a method by name.

  Waits for execution always. Independent of async.

  Returns one of:

  * {:ok, v}
  * {:error, e}

  """
  def call(pid, method, params, context) when is_pid(pid) do
    GenServer.call(pid, {:call, method, params, context}, 600_000)
  end
  def call(f, method, params, context) when is_function(f)  do
    try do
      f.(%RPC.Message{ method: method, params: params, context: context})
    rescue
      FunctionClauseError ->
        Logger.warn("Function method caller did not accept input. May be too strict.\n #{Exception.format_stacktrace}")
        {:error, :unknown_method}
      other ->
        Logger.error("#{Exception.format :error, other}")
        {:error, other}
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
              __dir(pid, context)
            end,
            [async: false, context: true]
          }
        },
      mc: [],
      guards: [],
      name: name
    }

    {:ok, state}
  end


  def handle_call({:debug}, _from, st) do
    %{
      methods: (Map.keys st.methods),
      mc: Enum.map(st.mc, fn
        {mc, options} when is_function(mc) ->
          name = Keyword.get options, :name, (inspect mc)
          "fn #{name}"
        {pid, _options} when is_pid(pid) ->
          debug(pid)
        _ ->
          "??"
      end)
    }
  end

  def handle_call({:dir, context}, _from, st) do
    local = st.methods
      |> Enum.flat_map(fn {name, {_, options}} ->
          if check_guards(%MOM.RPC.Message{ method: name, context: context}, options, st.guards) do
            [name]
          else
            []
          end
        end)
    other = Enum.flat_map( st.mc, fn {smc, options} ->
      if check_guards(%MOM.RPC.Message{ method: "dir", context: context}, options, st.guards) do
        __dir(smc, context)
      else
        []
      end
    end)
    res = Enum.uniq Enum.sort( local ++ other )
    {:reply, res, st}
  end

  def handle_call({:add_method, name, f, options}, _from, status) do
    {:reply, :ok, %{ status |
      methods: Map.put(status.methods, name, {f, options})
    }}
  end
  def handle_call({:add_method_caller, nmc, options}, _from, status) do
    {:reply, :ok, %{ status |
      mc: status.mc ++ [{nmc, options}]
    }}
  end
  def handle_call({:add_guard, name, guard_f}, _from, status) do
    {:reply, :ok, %{ status |
      guards: status.guards ++ [{name, guard_f}]
    }}
  end
  def handle_call({:call, "dir", _params, context}, from, status) do
    {:reply, dir, status} = handle_call({:dir, context}, from, status)
    {:reply, {:ok, dir}, status}
  end
  def handle_call({:call, method, params, context}, from, status) do
    #Logger.info("CALL Method #{method} caller pid #{status.name}, in #{inspect (Map.keys status.methods)} #{inspect Enum.map(status.mc, fn {f, options} -> Keyword.get options, :name, (inspect f) end) }")
    case Map.get status.methods, method do
      {f, options} ->
        # sync or async, default async
        #Logger.debug("CALL final function #{method}")
        if Keyword.get(options, :async, true) do
          Task.start( fn ->
            Logger.debug("Async!")
            ret = call_function_real(f, options, method, params, context, status)
            GenServer.reply(from, ret)
          end)
          # is being processed
          {:noreply, status}
        else
          res = call_function_real(f, options, method, params, context, status)
          {:reply, res, status}
        end
      nil ->
        # Look for it at method callers. Use a task to prevent blocking.
        if Enum.count(status.mc) > 0 do
          #Logger.debug("CALL Checking MCs #{inspect status.mc}/#{inspect method}")
          Task.start(fn ->
            res = call_method_callers(status.mc, method, params, context, status)
            #Logger.debug("CALL Got MC answer: #{method} -> #{inspect res} ")
            GenServer.reply(from, res)
            #Logger.debug("Call cast done #{inspect ret} at #{inspect self()}")
          end)
          {:noreply, status}
        else # no mcs, then nok
          {:reply, {:error, :unknown_method}, status}
        end
    end
  end

  # Checks all the guards, return false if any fails.
  defp check_guards(%MOM.RPC.Message{}, _, []), do: true
  defp check_guards(%MOM.RPC.Message{} = msg, options, [{gname, gf} | rest]) do
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

  @doc ~S"""
  Performs the real call to a function, checking guards, with the given params
  and so on.
  """
  def call_function_real(f, options, method, params, context, status) do
    Logger.debug("Call final function #{method}")
    if check_guards(%RPC.Message{ method: method, params: params, context: context}, options, status.guards) do
      res = try do
        v = if Keyword.get(options, :context, false) do
          #Logger.debug("Calling with context #{inspect f} #{inspect options} #{inspect self()}")
          f.(params, context)
        else
          #Logger.debug("Calling without context #{inspect f}")
          f.(params)
        end
        #Logger.debug("Method #{method} caller function #{inspect f} -> #{inspect v}.")
        case v do
          {:error, e} ->
            {:error, e }
          {:ok, v} ->
            {:ok, v }
          v ->
            {:ok, v }
        end
      rescue
        CaseClauseError ->
          Logger.error("Case clause error method #{method}\n#{Exception.format_stacktrace System.stacktrace}")
          {:error, :bad_arity}
        FunctionClauseError ->
          Logger.error("Function clause error method #{method}\n#{Exception.format_stacktrace System.stacktrace}")
          {:error, :bad_arity}
        BadArityError ->
          Logger.error("Bad arity error #{method}\n#{Exception.format_stacktrace System.stacktrace}")
          {:error, :bad_arity}
        e ->
          Logger.error("Error on method #{method}\n#{inspect e}\n#{Exception.format_stacktrace System.stacktrace}")
          {:error, e}
      end
      Logger.debug("Call final function #{method} -> #{inspect res}")
      res
    else # do not pass guards
      Logger.debug("Call final function #{method} -> fail guards")
      {:error, :unknown_method }
    end
  end

  def call_method_callers(mcs, method, params, context, status) do
    #ret = cast_mc(status.mc, method, params, context, status.guards)
    any = Enum.reduce_while(mcs, {:error, :unknown_method}, fn {mc, options}, acc ->
      if check_guards(
            %RPC.Message{ method: method, params: params, context: context},
            options, status.guards) do
        res = call(mc, method, params, context)
        #Logger.debug("Got #{inspect res} from #{inspect mc}")
        case res do
          {:error, :unknown_method} -> # cant run it at that MC
            {:cont, acc}
          :nok -> # cant run it at that MC
            {:cont, acc}
          res -> # ok!
            {:halt, res}
        end
      else
        # no guard
        {:cont, acc}
      end
    end)
  end

end
