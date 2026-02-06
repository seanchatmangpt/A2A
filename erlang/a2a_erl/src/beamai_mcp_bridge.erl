%%%-------------------------------------------------------------------
%%% @doc MCP Bridge: forwards between beamai Kernel tools and
%%% beamai_mcp_server.
%%%
%%% register_tools/0 reads all tools from a beamai Kernel (supplied
%%% by beamai_tool_bridge) and registers them as MCP tools on a
%%% running beamai_mcp_server instance. handle_request/2 and
%%% forward/2 relay MCP JSON-RPC traffic.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_mcp_bridge).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, register_tools/0, handle_request/2,
         forward/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    mcp_server :: pid() | undefined,
    registered :: [binary()]
}).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec register_tools() -> {ok, non_neg_integer()} | {error, term()}.
register_tools() ->
    gen_server:call(?MODULE, register_tools, ?DEFAULT_TIMEOUT).

-spec handle_request(binary(), map()) -> {ok, map()} | {error, term()}.
handle_request(Method, Params) ->
    gen_server:call(?MODULE, {handle_request, Method, Params}, ?DEFAULT_TIMEOUT).

-spec forward(binary(), map()) -> ok | {error, term()}.
forward(Method, Params) ->
    gen_server:cast(?MODULE, {forward, Method, Params}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    ?LOG_INFO("beamai_mcp_bridge started"),
    {ok, #state{mcp_server = undefined, registered = []}}.

handle_call(register_tools, _From, State) ->
    McpPid = resolve_mcp_server(State),
    case McpPid of
        undefined ->
            {reply, {error, mcp_server_not_running}, State};
        Pid ->
            Tools = beamai_tool_bridge:list_tools(),
            Count = lists:foldl(fun(ToolSpec, Acc) ->
                McpTool = kernel_tool_to_mcp(ToolSpec),
                case beamai_mcp_server:register_tool(Pid, McpTool) of
                    ok         -> Acc + 1;
                    {ok, _}    -> Acc + 1;
                    {error, _} -> Acc
                end
            end, 0, Tools),
            Names = [maps:get(name, T) || T <- Tools],
            {reply, {ok, Count},
             State#state{mcp_server = Pid, registered = Names}}
    end;

handle_call({handle_request, <<"tools/call">>, #{<<"name">> := Name} = Params}, _From, State) ->
    Args = maps:get(<<"arguments">>, Params, #{}),
    Reply = beamai_tool_bridge:execute(Name, Args, #{}),
    {reply, Reply, State};

handle_call({handle_request, <<"tools/list">>, _Params}, _From, State) ->
    Tools = beamai_tool_bridge:list_tools(),
    Specs = [beamai_tool:to_tool_spec(T) || T <- Tools],
    {reply, {ok, Specs}, State};

handle_call({handle_request, _Method, _Params}, _From, State) ->
    {reply, {error, method_not_supported}, State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({forward, Method, Params}, #state{mcp_server = Pid} = State)
  when Pid =/= undefined ->
    case beamai_mcp_server:handle_request(Pid,
            #{<<"jsonrpc">> => <<"2.0">>,
              <<"method">>  => Method,
              <<"params">>  => Params,
              <<"id">>      => erlang:unique_integer([positive])}) of
        _ -> ok
    end,
    {noreply, State};

handle_cast({forward, _Method, _Params}, State) ->
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal
%%====================================================================

resolve_mcp_server(#state{mcp_server = Pid}) when is_pid(Pid),
                                                    Pid =/= undefined ->
    case is_process_alive(Pid) of
        true  -> Pid;
        false -> find_mcp_server()
    end;
resolve_mcp_server(_) ->
    find_mcp_server().

find_mcp_server() ->
    case whereis(beamai_mcp_server) of
        undefined -> undefined;
        Pid       -> Pid
    end.

kernel_tool_to_mcp(#{name := Name} = ToolSpec) ->
    Desc = maps:get(description, ToolSpec, <<"">>),
    Params = maps:get(parameters, ToolSpec, #{}),
    Schema = beamai_tool:to_tool_spec(ToolSpec),
    InputSchema = maps:get(parameters, Schema, #{
        type => object, properties => #{}, required => []
    }),
    #{name => Name,
      description => Desc,
      input_schema => InputSchema}.
