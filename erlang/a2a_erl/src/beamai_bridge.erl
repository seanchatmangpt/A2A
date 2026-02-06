%%%-------------------------------------------------------------------
%%% @doc Main beamai bridge gen_server.
%%% Creates a beamai kernel on init, registers A2A handlers as beamai
%%% tools (via beamai:tool/3, beamai:add_tool/2), stores in ETS.
%%% Uses beamai:kernel/1, beamai:add_llm/2,3, beamai:add_filter/4,
%%% beamai:invoke_tool/4, beamai:context/1.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_bridge).
-behaviour(gen_server).

-export([start_link/0, start_link/1, get_kernel/0,
         register_a2a_handler/2, translate_task/1,
         translate_message/1, invoke_handler/3]).
-export([init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

-include_lib("beamai_core/include/beamai_common.hrl").

-define(SERVER, ?MODULE).
-define(ETS_TABLE, beamai_bridge_state).

-record(state, {
    kernel :: beamai_kernel:kernel(),
    handlers :: #{binary() => module()}
}).

%%====================================================================
%% API
%%====================================================================

start_link() -> start_link(#{}).

start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

-spec get_kernel() -> beamai_kernel:kernel().
get_kernel() ->
    gen_server:call(?SERVER, get_kernel, ?DEFAULT_TIMEOUT).

-spec register_a2a_handler(binary(), module()) -> ok | {error, term()}.
register_a2a_handler(Name, Module) ->
    gen_server:call(?SERVER, {register_handler, Name, Module}, ?DEFAULT_TIMEOUT).

-spec translate_task(map()) -> map().
translate_task(#{id := Id, status := #{state := State}} = Task) ->
    #{id => Id,
      status => beamai_a2a_types:task_state_to_binary(State),
      artifacts => maps:get(artifacts, Task, []),
      messages => maps:get(messages, Task, []),
      metadata => maps:get(metadata, Task, #{})};
translate_task(Task) -> Task.

-spec translate_message(map()) -> map().
translate_message(#{role := Role, parts := Parts}) ->
    #{role => beamai_a2a_types:role_to_binary(Role),
      content => extract_text_parts(Parts)};
translate_message(Msg) -> Msg.

-spec invoke_handler(binary(), map(), map()) -> {ok, term()} | {error, term()}.
invoke_handler(Name, Args, Ctx) ->
    gen_server:call(?SERVER, {invoke, Name, Args, Ctx}, ?DEFAULT_LLM_TIMEOUT).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init(Opts) ->
    ets:new(?ETS_TABLE, [named_table, public, set, {read_concurrency, true}]),
    Settings = maps:get(kernel_settings, Opts, #{}),
    K0 = beamai:kernel(Settings),
    K1 = case maps:get(llm_config, Opts, undefined) of
        undefined -> K0;
        #{provider := Provider, opts := LlmOpts} ->
            beamai:add_llm(K0, Provider, LlmOpts);
        LlmCfg when is_map(LlmCfg) ->
            beamai:add_llm(K0, LlmCfg)
    end,
    K2 = beamai:add_filter(K1, <<"a2a_bridge_log">>, pre_invocation,
        fun(Fc) ->
            ?LOG_DEBUG("beamai_bridge: tool=~p", [maps:get(tool, Fc, undefined)]),
            {continue, Fc}
        end),
    ets:insert(?ETS_TABLE, {kernel, K2}),
    {ok, #state{kernel = K2, handlers = #{}}}.

handle_call(get_kernel, _From, #state{kernel = K} = S) ->
    {reply, K, S};
handle_call({register_handler, Name, Module}, _From, State) ->
    #state{kernel = K0, handlers = H} = State,
    Handler = fun(Args, _Ctx) ->
        try Module:process(Args, #{}) of
            {ok, R} -> {ok, R};
            {error, R} -> {error, R};
            Other -> {ok, Other}
        catch C:R -> {error, {C, R}}
        end
    end,
    Tool = beamai:tool(Name, Handler, #{
        description => <<"A2A handler: ", Name/binary>>,
        tag => <<"a2a">>
    }),
    K1 = beamai:add_tool(K0, Tool),
    ets:insert(?ETS_TABLE, {kernel, K1}),
    {reply, ok, State#state{kernel = K1, handlers = H#{Name => Module}}};
handle_call({invoke, Name, Args, Ctx}, _From, #state{kernel = K} = S) ->
    Context = beamai:context(Ctx),
    Reply = case beamai:invoke_tool(K, Name, Args, Context) of
        {ok, Value, _NewCtx} -> {ok, Value};
        {error, _} = Err -> Err
    end,
    {reply, Reply, S};
handle_call(_Request, _From, S) ->
    {reply, {error, unknown_request}, S}.

handle_cast(_Msg, S) -> {noreply, S}.
handle_info(_Info, S) -> {noreply, S}.
terminate(_Reason, _S) -> catch ets:delete(?ETS_TABLE), ok.
code_change(_OldVsn, S, _Extra) -> {ok, S}.

%%====================================================================
%% Internal
%%====================================================================

extract_text_parts(Parts) when is_list(Parts) ->
    case [T || #{kind := text, text := T} <- Parts] of
        [] -> <<>>;
        [Single] -> Single;
        Multiple -> iolist_to_binary(lists:join(<<"\n">>, Multiple))
    end;
extract_text_parts(_) -> <<>>.
