%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI YAWL Resource Bridge
%%%
%%% gen_server that registers YAWL resources as beamai tools via
%%% beamai:tool/3. Each YAWL resource becomes a tool whose handler
%%% delegates execution to the underlying resource through
%%% yawl_resource_manager.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_yawl_resource_bridge).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% API
-export([start_link/0, register_resources/1, allocate/2,
         release/2, get_available/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    registered = #{} :: #{binary() => map()},
    kernel     = undefined :: term()
}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec register_resources([map()]) -> {ok, [binary()]} | {error, term()}.
register_resources(Resources) ->
    gen_server:call(?MODULE, {register_resources, Resources}).

-spec allocate(binary(), map()) -> {ok, binary()} | {error, term()}.
allocate(ResourceType, Requirements) ->
    gen_server:call(?MODULE, {allocate, ResourceType, Requirements}).

-spec release(binary(), binary()) -> ok | {error, term()}.
release(WorkitemId, ResourceId) ->
    gen_server:call(?MODULE, {release, WorkitemId, ResourceId}).

-spec get_available(binary()) -> {ok, [map()]} | {error, term()}.
get_available(ResourceType) ->
    gen_server:call(?MODULE, {get_available, ResourceType}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    Kernel = beamai_kernel:new(#{name => <<"yawl_resources">>}),
    {ok, #state{kernel = Kernel}}.

handle_call({register_resources, Resources}, _From, State) ->
    {Ids, NewState} = lists:foldl(fun(Res, {AccIds, AccState}) ->
        {Id, S} = do_register_resource(Res, AccState),
        {[Id | AccIds], S}
    end, {[], State}, Resources),
    {reply, {ok, lists:reverse(Ids)}, NewState};

handle_call({allocate, ResourceType, Requirements}, _From, State) ->
    Caps = maps:get(capabilities, Requirements, []),
    WorkitemId = maps:get(workitem_id, Requirements,
                          integer_to_binary(erlang:unique_integer([positive]))),
    case yawl_resource_manager:allocate_resource(
           WorkitemId, binary_to_existing_atom(ResourceType, utf8), Caps) of
        {ok, ResourceId, _ResourceMap} ->
            {reply, {ok, ResourceId}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({release, WorkitemId, ResourceId}, _From, State) ->
    Reply = yawl_resource_manager:release_resource(WorkitemId, ResourceId),
    {reply, Reply, State};

handle_call({get_available, ResourceType}, _From, State) ->
    Reply = yawl_resource_manager:list_resources_by_type(
              binary_to_existing_atom(ResourceType, utf8)),
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

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

do_register_resource(#{resource_id := ResId, name := Name,
                       resource_type := Type} = Res, State) ->
    Handler = make_resource_handler(ResId, Type),
    ToolName = <<"resource_", Name/binary>>,
    Tool = beamai:tool(ToolName, Handler, #{
        description => <<"YAWL resource: ", Name/binary,
                         " (", (atom_to_binary(Type, utf8))/binary, ")">>
    }),
    NewKernel = beamai_kernel:add_tool(State#state.kernel, Tool),
    NewRegistered = maps:put(ResId, Res, State#state.registered),
    {ResId, State#state{kernel = NewKernel, registered = NewRegistered}};
do_register_resource(#{name := Name, resource_type := Type} = Res, State) ->
    ResId = generate_id(Name),
    do_register_resource(Res#{resource_id => ResId}, State).

make_resource_handler(ResourceId, _Type) ->
    fun(Args) ->
        WorkitemId = maps:get(workitem_id, Args,
                              integer_to_binary(erlang:unique_integer([positive]))),
        Caps = maps:get(capabilities, Args, []),
        case yawl_resource_manager:allocate_resource(WorkitemId, Caps) of
            {ok, ResourceId, ResMap} ->
                #{status => allocated, resource_id => ResourceId,
                  resource => ResMap};
            {error, Reason} ->
                #{status => error, reason => Reason}
        end
    end.

generate_id(Name) ->
    Ts = integer_to_binary(erlang:system_time(millisecond)),
    <<"res_", Name/binary, "_", Ts/binary>>.
