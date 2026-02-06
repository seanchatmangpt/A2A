%%%-------------------------------------------------------------------
%%% @doc Tool Bridge: registers A2A handlers and services as beamai tools
%%%
%%% Wraps a2a_handler callbacks and yawl_service_registry entries
%%% into beamai tool specs via beamai:tool/3, and manages a Kernel
%%% holding all registered tools.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_tool_bridge).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, register_handler/2, register_service/2,
         list_tools/0, execute/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    kernel :: beamai_kernel:kernel(),
    handlers :: #{binary() => module()}
}).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec register_handler(binary(), module()) -> ok | {error, term()}.
register_handler(Name, HandlerMod) ->
    gen_server:call(?MODULE, {register_handler, Name, HandlerMod}).

-spec register_service(binary(), binary()) -> ok | {error, term()}.
register_service(Name, ServiceName) ->
    gen_server:call(?MODULE, {register_service, Name, ServiceName}).

-spec list_tools() -> [beamai_tool:tool_spec()].
list_tools() ->
    gen_server:call(?MODULE, list_tools).

-spec execute(binary(), map(), map()) -> {ok, term()} | {error, term()}.
execute(ToolName, Args, Ctx) ->
    gen_server:call(?MODULE, {execute, ToolName, Args, Ctx}, ?DEFAULT_TIMEOUT).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    Kernel = beamai_kernel:new(#{max_tool_iterations => 10}),
    ?LOG_INFO("beamai_tool_bridge started"),
    {ok, #state{kernel = Kernel, handlers = #{}}}.

handle_call({register_handler, Name, HandlerMod}, _From, State) ->
    Handler = fun(Args) ->
        TaskStub = #{id => Name, status => #{state => working}},
        MsgStub  = #{role => <<"user">>, parts => [Args]},
        case HandlerMod:init(TaskStub, MsgStub) of
            {ok, HState} ->
                case HandlerMod:process(TaskStub, HState) of
                    {ok, Result}             -> {ok, Result};
                    {error, Reason}          -> {error, Reason};
                    {input_required, Prompt} -> {ok, #{input_required => Prompt}}
                end;
            {error, Reason} ->
                {error, Reason}
        end
    end,
    ToolSpec = beamai:tool(Name, Handler, #{
        description => <<"A2A handler: ", Name/binary>>,
        tag         => <<"a2a_handler">>
    }),
    Kernel = beamai:add_tool(State#state.kernel, ToolSpec),
    Handlers = maps:put(Name, HandlerMod, State#state.handlers),
    {reply, ok, State#state{kernel = Kernel, handlers = Handlers}};

handle_call({register_service, Name, ServiceName}, _From, State) ->
    Handler = fun(Args) ->
        case yawl_service_registry:call_service(ServiceName, Args) of
            {ok, Result} -> {ok, Result};
            {error, Reason} -> {error, Reason}
        end
    end,
    ToolSpec = beamai:tool(Name, Handler, #{
        description => <<"Service: ", ServiceName/binary>>,
        tag         => <<"service">>
    }),
    Kernel = beamai:add_tool(State#state.kernel, ToolSpec),
    {reply, ok, State#state{kernel = Kernel}};

handle_call(list_tools, _From, #state{kernel = Kernel} = State) ->
    Tools = beamai_kernel:list_tools(Kernel),
    {reply, Tools, State};

handle_call({execute, ToolName, Args, _Ctx}, _From, #state{kernel = Kernel} = State) ->
    Context = beamai_context:new(),
    Reply = case beamai_kernel:invoke_tool(Kernel, ToolName, Args, Context) of
        {ok, Value, _NewCtx} -> {ok, Value};
        {error, _} = Err     -> Err
    end,
    {reply, Reply, State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
