%%%-------------------------------------------------------------------
%%% @doc BeamAI Filter pipeline.
%%% Manages pre/post invocation and chat filters that can transform
%%% data flowing through the kernel. Filters are executed in order
%%% of registration (or priority when specified).
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_filter).

-export([
    new/1,
    new/3,
    apply_filters/3,
    sort_by_priority/1
]).

-type filter_stage() :: pre_invoke | post_invoke | pre_chat | post_chat | all.
-type filter_def() :: #{
    name := binary(),
    stage := filter_stage(),
    priority := integer(),
    function := fun((map()) -> map())
}.

-export_type([filter_stage/0, filter_def/0]).

%%--------------------------------------------------------------------
%% @doc Create a global filter (applies to all stages) from a function.
%% @end
%%--------------------------------------------------------------------
-spec new(fun((map()) -> map())) -> filter_def().
new(FilterFun) when is_function(FilterFun, 1) ->
    #{
        name => <<"anonymous_filter">>,
        stage => all,
        priority => 100,
        function => FilterFun
    }.

%%--------------------------------------------------------------------
%% @doc Create a named filter for a specific stage.
%% @end
%%--------------------------------------------------------------------
-spec new(filter_stage(), binary(), fun((map()) -> map())) -> filter_def().
new(Stage, Name, FilterFun) when is_function(FilterFun, 1) ->
    #{
        name => Name,
        stage => Stage,
        priority => 100,
        function => FilterFun
    }.

%%--------------------------------------------------------------------
%% @doc Apply all matching filters for a given stage to the data.
%% Filters are applied in sequence; each filter receives the output
%% of the previous one. Only filters matching the stage (or 'all')
%% are applied.
%% @end
%%--------------------------------------------------------------------
-spec apply_filters(filter_stage(), [filter_def()], map()) -> map().
apply_filters(Stage, Filters, Data) ->
    MatchingFilters = [
        F || F = #{stage := S} <- Filters,
        S =:= Stage orelse S =:= all
    ],
    Sorted = sort_by_priority(MatchingFilters),
    lists:foldl(
        fun(#{function := Fun}, AccData) ->
            try
                Fun(AccData)
            catch
                Class:Reason:Stack ->
                    logger:warning("Filter failed (~p:~p): ~p", [Class, Reason, Stack]),
                    AccData
            end
        end,
        Data,
        Sorted
    ).

%%--------------------------------------------------------------------
%% @doc Sort filter definitions by priority (lower number = higher priority).
%% @end
%%--------------------------------------------------------------------
-spec sort_by_priority([filter_def()]) -> [filter_def()].
sort_by_priority(Filters) ->
    lists:sort(
        fun(#{priority := P1}, #{priority := P2}) -> P1 =< P2 end,
        Filters
    ).
