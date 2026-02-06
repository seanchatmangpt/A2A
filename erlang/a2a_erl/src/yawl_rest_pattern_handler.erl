%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Pattern REST API Handler
%%%
%%% This module provides HTTP REST API endpoints for YAWL workflow
%%% pattern management including pattern listing, validation,
%%% and detailed pattern information.
%%%
%%% ## Endpoints
%%%
%%% - `GET /patterns` - List all available workflow patterns
%%% - `GET /patterns/{type}` - Get detailed information about a specific pattern
%%% - `GET /patterns/categories` - List pattern categories
%%% - `GET /patterns/validate` - Validate a pattern configuration
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_pattern_handler).
-author("A2A Team").

%% Cowboy handler exports
-export([
    init/2,
    allowed_methods/2,
    content_types_provided/2,
    resource_exists/2,
    to_json/2
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    method :: cowboy_http:method(),
    pattern_type :: binary() | undefined,
    action :: binary() | undefined
}).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, State) ->
    Method = cowboy_req:method(Req),
    PatternType = cowboy_req:binding(pattern_type, Req),
    Action = cowboy_req:binding(action, Req),

    NewState = #state{
        method = Method,
        pattern_type = PatternType,
        action = Action
    },

    {cowboy_rest, Req, NewState}.

%% @private
allowed_methods(Req, State) ->
    Methods = case State#state.pattern_type of
        undefined when State#state.action =:= undefined ->
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        undefined ->
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        _ when State#state.action =:= undefined ->
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>];
        _ ->
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>]
    end,
    {Methods, Req, State}.

%% @private
content_types_provided(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, '*'}, to_json},
        {{<<"application">>, <<"vnd.api+json">>, '*'}, to_json}
    ], Req, State}.

%% @private
resource_exists(Req, State) ->
    Exists = case State#state.pattern_type of
        undefined -> true;  %% Collection resource
        PatternTypeBin ->
            PatternType = try binary_to_existing_atom(PatternTypeBin, utf8)
            catch error:badarg -> undefined
            end,
            PatternType =/= undefined andalso lists:member(PatternType, ?YAWL_PATTERNS)
    end,
    {Exists, Req, State}.

%% @private
to_json(Req, State) ->
    Response = case {State#state.pattern_type, State#state.action} of
        {undefined, undefined} ->
            handle_list_patterns();
        {PatternTypeBin, undefined} ->
            handle_get_pattern_info(PatternTypeBin);
        {undefined, <<"categories">>} ->
            handle_list_categories();
        {undefined, <<"validate">>} ->
            handle_validate_pattern(Req);
        {undefined, Action} ->
            #{error => <<"unknown_action">>, action => Action};
        {_, _} ->
            #{error => <<"invalid_request">>}
    end,

    Body = jiffy:encode(Response),
    {Body, Req, State}.

%%====================================================================
%% Handler Functions
%%====================================================================

%% @private
handle_list_patterns() ->
    Patterns = yawl_patterns:list_patterns(),
    PatternSummaries = lists:map(fun(PatternType) ->
        Info = yawl_patterns:get_pattern_info(PatternType),
        #{
            type => PatternType,
            name => maps:get(name, Info, <<"unknown">>),
            description => maps:get(description, Info, <<"">>),
            complexity => maps:get(complexity, Info, medium)
        }
    end, Patterns),

    #{
        patterns => PatternSummaries,
        total => length(Patterns),
        categories => get_pattern_categories()
    }.

%% @private
handle_get_pattern_info(PatternTypeBin) ->
    PatternType = binary_to_existing_atom(PatternTypeBin, utf8),
    Info = yawl_patterns:get_pattern_info(PatternType),

    #{
        type => PatternType,
        name => maps:get(name, Info, <<"unknown">>),
        description => maps:get(description, Info, <<"">>),
        complexity => maps:get(complexity, Info, medium),
        places => maps:get(places, Info, []),
        transitions => maps:get(transitions, Info, []),
        category => categorize_pattern(PatternType),
        required_params => get_required_params(PatternType),
        optional_params => get_optional_params(PatternType),
        example_config => get_example_config(PatternType)
    }.

%% @private
handle_list_categories() ->
    #{
        categories => get_pattern_categories(),
        total => length(get_pattern_categories())
    }.

%% @private
handle_validate_pattern(Req) ->
    %% Parse query parameters for validation
    QS = cowboy_req:qs(Req),
    Params = parse_query_string(QS),

    PatternTypeBin = maps_get(<<"pattern_type">>, Params, undefined),
    ConfigJson = maps_get(<<"config">>, Params, <<"{}">>),

    Response = case PatternTypeBin of
        undefined ->
            #{error => <<"missing_pattern_type">>, message => <<"pattern_type parameter is required">>};
        _ ->
            PatternType = try binary_to_existing_atom(PatternTypeBin, utf8)
            catch error:badarg -> undefined
            end,

            case PatternType of
                undefined ->
                    #{error => <<"invalid_pattern_type">>, pattern_type => PatternTypeBin};
                _ ->
                    Config = try jiffy:decode(ConfigJson, [return_maps])
                    catch _:_ -> #{}
                    end,

                    Valid = yawl_patterns:validate_pattern(PatternType, Config),
                    #{
                        pattern_type => PatternType,
                        valid => Valid,
                        config => Config
                    }
            end
    end,

    Response.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
get_pattern_categories() -> [
    #{name => <<"basic">>, description => <<"Basic workflow patterns">>,
      patterns => [basic_sequential, simple_merge]},
    #{name => <<"branching">>, description => <<"Control-flow branching patterns">>,
      patterns => [exclusive_choice, parallel_split, parallel_join]},
    #{name => <<"advanced">>, description => <<"Advanced workflow patterns">>,
      patterns => [iterative_loop, multi_instance, interleaved_parallelism]},
    #{name => <<"cancellation">>, description => <<"Cancellation patterns">>,
      patterns => [cancelation, cancelation_block, cancelation_scope, cancelation_thread]}
].

%% @private
categorize_pattern(PatternType) ->
    Categories = [
        {basic, [basic_sequential, simple_merge, implicit_merge, multiple_merge]},
        {branching, [exclusive_choice, parallel_split, parallel_join,
                     deferred_choice, interleaved_routing]},
        {advanced, [iterative_loop, multi_instance, interleaved_parallelism,
                    milestone]},
        {cancellation, [cancelation, cancelation_block, cancelation_scope,
                        cancelation_thread, cancelation_subprocess,
                        cancelation_multiple_instances]}
    ],

    case lists:keyfind(PatternType, 2, Categories) of
        {Category, _} -> Category;
        false -> other
    end.

%% @private
get_required_params(basic_sequential) -> [];
get_required_params(parallel_split) -> [branches];
get_required_params(parallel_join) -> [branches];
get_required_params(exclusive_choice) -> [conditions];
get_required_params(iterative_loop) -> [condition];
get_required_params(multi_instance) -> [num_instances, data];
get_required_params(_) -> [].

%% @private
get_optional_params(basic_sequential) -> [timeout, retry_policy];
get_optional_params(parallel_split) -> [timeout];
get_optional_params(parallel_join) -> [timeout];
get_optional_params(exclusive_choice) -> [default_branch];
get_optional_params(iterative_loop) -> [max_iterations];
get_optional_params(multi_instance) -> [allocation_strategy];
get_optional_params(_) -> [timeout, retry_policy].

%% @private
get_example_config(basic_sequential) ->
    #{
        tasks => [
            #{name => <<"task1">>, type => <<"service">>},
            #{name => <<"task2">>, type => <<"service">>}
        ]
    };
get_example_config(parallel_split) ->
    #{
        branches => 3,
        tasks => [
            #{name => <<"parallel_task_1">>},
            #{name => <<"parallel_task_2">>},
            #{name => <<"parallel_task_3">>}
        ]
    };
get_example_config(exclusive_choice) ->
    #{
        conditions => [
            #{name => <<"condition_a">>, expression => <<"data.value > 10">>},
            #{name => <<"condition_b">>, expression => <<"data.value <= 10">>}
        ],
        default_branch => condition_b
    };
get_example_config(iterative_loop) ->
    #{
        condition => <<"data.count < data.max">>,
        max_iterations => 100,
        task => #{name => <<"process_item">>}
    };
get_example_config(multi_instance) ->
    #{
        num_instances => 5,
        data => [#{id => 1}, #{id => 2}, #{id => 3}, #{id => 4}, #{id => 5}],
        task => #{name => <<"process_data">>}
    };
get_example_config(_) -> #{}.

%% @private
parse_query_string(<<>>) ->
    #{};
parse_query_string(QS) ->
    parse_query_params(binary:split(QS, <<"&">>), #{}).

%% @private
parse_query_params([], Acc) ->
    Acc;
parse_query_params([Pair | Rest], Acc) ->
    case binary:split(Pair, <<"=">>) of
        [Key, Value] ->
            DecodedKey = uri_string:unquote(Key),
            DecodedValue = uri_string:unquote(Value),
            parse_query_params(Rest, Acc#{DecodedKey => DecodedValue});
        [Key] ->
            DecodedKey = uri_string:unquote(Key),
            parse_query_params(Rest, Acc#{DecodedKey => true})
    end.

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
