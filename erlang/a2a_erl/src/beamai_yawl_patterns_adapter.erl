%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI YAWL Patterns Adapter
%%%
%%% Pure function module that converts YAWL workflow patterns into
%%% beamai process steps. Each YAWL pattern maps to a structured
%%% process definition that beamai_process_agent can execute.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_yawl_patterns_adapter).

-include_lib("beamai_core/include/beamai_common.hrl").
-include("yawl_types.hrl").

%% API
-export([adapt_pattern/1, to_process_step/1, from_process_result/1,
         validate_pattern/1]).

%%====================================================================
%% API
%%====================================================================

-spec adapt_pattern(atom()) -> map().
adapt_pattern(sequence) ->
    #{type => sequential, steps => [], flow => linear};
adapt_pattern(basic_sequential) ->
    #{type => sequential, steps => [], flow => linear};
adapt_pattern(parallel_split) ->
    #{type => parallel, branches => [], join => sync_all};
adapt_pattern(parallel_join) ->
    #{type => parallel, branches => [], join => barrier};
adapt_pattern(exclusive_choice) ->
    #{type => conditional, conditions => [], default => undefined};
adapt_pattern(simple_merge) ->
    #{type => conditional, conditions => [], merge => first_completed};
adapt_pattern(deferred_choice) ->
    #{type => event_driven, events => [], selection => runtime};
adapt_pattern(iterative_loop) ->
    #{type => loop, condition => undefined, body => [], max_iterations => 100};
adapt_pattern(multi_instance) ->
    #{type => parallel, branches => [], join => sync_all, dynamic => true};
adapt_pattern(interleaved_parallelism) ->
    #{type => interleaved, tasks => [], mutex => true};
adapt_pattern(milestone) ->
    #{type => milestone, condition => undefined, guarded_steps => []};
adapt_pattern(cancelation) ->
    #{type => cancellable, scope => all, cancel_handler => undefined};
adapt_pattern(cancelation_block) ->
    #{type => cancellable, scope => block, cancel_handler => undefined};
adapt_pattern(cancelation_scope) ->
    #{type => cancellable, scope => region, cancel_handler => undefined};
adapt_pattern(Pattern) ->
    PatternBin = atom_to_binary(Pattern, utf8),
    case PatternBin of
        <<"cancelation_", _/binary>> ->
            #{type => cancellable, scope => Pattern, cancel_handler => undefined};
        _ ->
            #{type => sequential, steps => [], pattern => Pattern}
    end.

-spec to_process_step(map()) -> map().
to_process_step(#{type := sequential, steps := Steps}) ->
    ToolSteps = lists:map(fun step_to_tool_invocation/1, Steps),
    #{action => sequence, tools => ToolSteps};
to_process_step(#{type := parallel, branches := Branches}) ->
    BranchSteps = lists:map(fun step_to_tool_invocation/1, Branches),
    #{action => parallel, tools => BranchSteps};
to_process_step(#{type := conditional, conditions := Conditions}) ->
    Guards = lists:map(fun({Guard, Step}) ->
        #{guard => Guard, tool => step_to_tool_invocation(Step)}
    end, Conditions),
    #{action => conditional, branches => Guards};
to_process_step(#{type := event_driven, events := Events}) ->
    Handlers = lists:map(fun({Event, Step}) ->
        #{event => Event, tool => step_to_tool_invocation(Step)}
    end, Events),
    #{action => event_select, handlers => Handlers};
to_process_step(#{type := loop, condition := Cond, body := Body}) ->
    #{action => loop, condition => Cond,
      body => lists:map(fun step_to_tool_invocation/1, Body)};
to_process_step(#{type := cancellable, scope := Scope}) ->
    #{action => cancellable, scope => Scope};
to_process_step(#{type := interleaved, tasks := Tasks}) ->
    #{action => interleave,
      tools => lists:map(fun step_to_tool_invocation/1, Tasks)};
to_process_step(#{type := milestone, guarded_steps := Steps}) ->
    #{action => milestone,
      tools => lists:map(fun step_to_tool_invocation/1, Steps)};
to_process_step(Other) ->
    #{action => passthrough, data => Other}.

-spec from_process_result(map()) -> map().
from_process_result(#{status := completed, result := Result}) ->
    #{workflow_status => completed, data => Result,
      completed_at => erlang:system_time(millisecond)};
from_process_result(#{status := failed, error := Error}) ->
    #{workflow_status => failed, error => Error,
      failed_at => erlang:system_time(millisecond)};
from_process_result(#{status := cancelled}) ->
    #{workflow_status => cancelled,
      cancelled_at => erlang:system_time(millisecond)};
from_process_result(Result) ->
    #{workflow_status => completed, data => Result,
      completed_at => erlang:system_time(millisecond)}.

-spec validate_pattern(atom()) -> boolean().
validate_pattern(Pattern) ->
    Known = [sequence, basic_sequential, parallel_split, parallel_join,
             exclusive_choice, simple_merge, deferred_choice, iterative_loop,
             multi_instance, interleaved_parallelism, milestone, cancelation,
             cancelation_block, cancelation_scope, cancelation_thread,
             cancelation_subprocess, cancelation_multiple_instances],
    lists:member(Pattern, Known) orelse
        is_extended_cancel_pattern(Pattern).

%%====================================================================
%% Internal
%%====================================================================

step_to_tool_invocation(#{name := Name} = Step) ->
    ToolName = ensure_binary(Name),
    Args = maps:get(args, Step, #{}),
    beamai:tool(ToolName, fun(A) -> maps:merge(Args, A) end);
step_to_tool_invocation(Name) when is_atom(Name) ->
    beamai:tool(atom_to_binary(Name, utf8), fun(A) -> A end);
step_to_tool_invocation(Name) when is_binary(Name) ->
    beamai:tool(Name, fun(A) -> A end).

ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V)   -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V)   -> list_to_binary(V).

is_extended_cancel_pattern(Pattern) ->
    Bin = atom_to_binary(Pattern, utf8),
    case Bin of
        <<"cancelation_", _/binary>> -> true;
        _ -> false
    end.
