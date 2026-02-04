%%% @doc Craftplan MCP-A2A Bridge
%%% Bridges MCP tools to A2A skills for agent collaboration

-module(craftplan_a2a_bridge).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([register_skills/0, tool_to_skill/1, skill_to_tool/1]).
-export([handle_a2a_task/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

%% Mapping of MCP tools to A2A skills
-define(TOOL_SKILL_MAP, #{
    <<"customer_management">> => <<"customer_management">>,
    <<"order_management">> => <<"order_management">>,
    <<"inventory_management">> => <<"inventory_management">>,
    <<"production_planning">> => <<"production_planning">>,
    <<"analytics">> => <<"analytics">>,
    <<"shipping">> => <<"shipping">>
}).

-record(state, {
    registered_skills :: map(),
    mcp_server :: pid() | undefined,
    a2a_handler :: pid() | undefined
}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

%% @doc Register all MCP tools as A2A skills
-spec register_skills() -> ok.
register_skills() ->
    gen_server:call(?SERVER, register_skills).

%% @doc Convert MCP tool name to A2A skill name
-spec tool_to_skill(binary()) -> binary().
tool_to_skill(ToolName) ->
    maps:get(ToolName, ?TOOL_SKILL_MAP, ToolName).

%% @doc Convert A2A skill name to MCP tool name
-spec skill_to_tool(binary()) -> binary().
skill_to_tool(SkillName) ->
    Maps = maps:iterator(?TOOL_SKILL_MAP),
    skill_to_tool_iter(maps:next(Maps), SkillName).

skill_to_tool_iter(none, _SkillName) -> undefined;
skill_to_tool_iter({Tool, Skill, _Iter}, SkillName) when Skill =:= SkillName -> Tool;
skill_to_tool_iter({_Tool, _Skill, Iter}, SkillName) ->
    skill_to_tool_iter(maps:next(Iter), SkillName).

%% @doc Handle an A2A task that invokes a skill (MCP tool)
-spec handle_a2a_task(binary(), map()) -> {ok, map()} | {error, term()}.
handle_a2a_task(SkillName, Params) ->
    ToolName = skill_to_tool(SkillName),
    case ToolName of
        undefined ->
            {error, {unknown_skill, SkillName}};
        _ ->
            craftplan_mcp_server:call_tool(ToolName, Params)
    end.

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    State = #state{
        registered_skills = #{},
        mcp_server = undefined,
        a2a_handler = undefined
    },

    %% Auto-register on init
    {ok, State1} = handle_call(register_skills, undefined, State),

    io:format("Craftplan A2A Bridge initialized~n"),
    {ok, State1}.

handle_call(register_skills, _From, State) ->
    %% Register skills with the A2A handler
    Skills = [
        #{
            <<"id">> => <<"customer_management">>,
            <<"name">> => <<"Customer Management">>,
            <<"description">> => <<"Manage customer records in Craftplan ERP">>,
            <<"input_schema">> => customer_input_schema()
        },
        #{
            <<"id">> => <<"order_management">>,
            <<"name">> => <<"Order Management">>,
            <<"description">> => <<"Create, update, and process orders">>,
            <<"input_schema">> => order_input_schema()
        },
        #{
            <<"id">> => <<"inventory_management">>,
            <<"name">> => <<"Inventory Management">>,
            <<"description">> => <<"Manage products and inventory">>,
            <<"input_schema">> => inventory_input_schema()
        },
        #{
            <<"id">> => <<"production_planning">>,
            <<"name">> => <<"Production Planning">>,
            <<"description">> => <<"Plan and track production orders">>,
            <<"input_schema">> => production_input_schema()
        },
        #{
            <<"id">> => <<"analytics">>,
            <<"name">> => <<"Business Analytics">>,
            <<"description">> => <<"Generate business reports">>,
            <<"input_schema">> => analytics_input_schema()
        },
        #{
            <<"id">> => <<"shipping">>,
            <<"name">> => <<"Shipping & Fulfillment">>,
            <<"description">> => <<"Process shipments and tracking">>,
            <<"input_schema">> => shipping_input_schema()
        }
    ],

    SkillsMap = maps:from_list([{maps:get(<<"id">>, S), S} || S <- Skills]),

    io:format("Registered ~p A2A skills~n", [length(Skills)]),

    {reply, ok, State#state{registered_skills = SkillsMap}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% Input schemas (same as in MCP server)
customer_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{<<"type">> => <<"string">>},
        <<"customer_id">> => #{<<"type">> => <<"string">>},
        <<"customer_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

order_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{<<"type">> => <<"string">>},
        <<"order_id">> => #{<<"type">> => <<"string">>},
        <<"order_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

inventory_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{<<"type">> => <<"string">>},
        <<"product_id">> => #{<<"type">> => <<"string">>},
        <<"quantity">> => #{<<"type">> => <<"integer">>}
    },
    <<"required">> => [<<"operation">>]
}.

production_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{<<"type">> => <<"string">>},
        <<"production_order_id">> => #{<<"type">> => <<"string">>},
        <<"order_data">> => #{<<"type">> => <<"object">>}
    },
    <<"required">> => [<<"operation">>]
}.

analytics_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"report_type">> => #{<<"type">> => <<"string">>},
        <<"date_range">> => #{<<"type">> => <<"object">>},
        <<"group_by">> => #{<<"type">> => <<"string">>}
    },
    <<"required">> => [<<"report_type">>]
}.

shipping_input_schema() -> #{
    <<"type">> => <<"object">>,
    <<"properties">> => #{
        <<"operation">> => #{<<"type">> => <<"string">>},
        <<"order_id">> => #{<<"type">> => <<"string">>},
        <<"tracking_number">> => #{<<"type">> => <<"string">>}
    },
    <<"required">> => [<<"operation">>]
}.
