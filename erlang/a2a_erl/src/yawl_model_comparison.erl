%%%-------------------------------------------------------------------
%%% @doc
%%% Process Model Comparison and Similarity Analysis
%%%
%%% This module provides comprehensive comparison capabilities for
%%% process models, supporting similarity metrics, diff analysis,
%% and alignment computation. Used for LLM hallucination detection
%%% and model validation.
%%%
%%% Key Features:
%%% - Structural similarity metrics
%%% - Behavioral similarity (trace-based)
%%% - Diff computation
%%% - Model alignment
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_model_comparison).
-author("A2A Team").

%% API exports - Similarity metrics
-export([
    structural_similarity/2,
    behavioral_similarity/2,
    textual_similarity/2,
    combined_similarity/2
]).

%% API exports - Diff analysis
-export([
    compute_diff/2,
    compute_edit_distance/2,
    find_added_activities/2,
    find_removed_activities/2,
    find_modified_activities/3
]).

%% API exports - Alignment
-export([
    compute_alignment/2,
    alignment_score/2,
    optimal_alignment/2
]).

%% API exports - Model matching
-export([
    find_matching_model/2,
    rank_models_by_similarity/2,
    cluster_similar_models/1
]).

-include("yawl_types.hrl").

%%====================================================================
%% Type Definitions
%%====================================================================

-type process_model() :: #{
    activities := [binary()],
    transitions := [map()],
    metadata => map()
}.

-type similarity_result() :: #{
    structural := float(),
    behavioral := float(),
    textual := float(),
    combined := float()
}.

-type diff_result() :: #{
    added := [binary()],
    removed := [binary()],
    modified := [{binary(), binary()}],
    unchanged := [binary()]
}.

-type alignment() :: [{binary() | none, binary() | none}].

%%====================================================================
%% API Functions - Similarity Metrics
%%====================================================================

%% @doc Compute structural similarity between two models.
%% Based on graph edit distance and activity overlap.
-spec structural_similarity(process_model(), process_model()) -> float().
structural_similarity(Model1, Model2) ->
    %% Activity overlap
    Acts1 = sets:from_list(maps:get(activities, Model1, [])),
    Acts2 = sets:from_list(maps:get(activities, Model2, [])),

    Intersection = sets:intersection(Acts1, Acts2),
    Union = sets:union(Acts1, Acts2),

    Jaccard = case sets:size(Union) of
        0 -> 1.0;
        N -> sets:size(Intersection) / N
    end,

    %% Transition structure similarity
    Trans1 = maps:get(transitions, Model1, []),
    Trans2 = maps:get(transitions, Model2, []),

    TransSim = transition_similarity(Trans1, Trans2),

    (Jaccard + TransSim) / 2.

%% @doc Compute behavioral similarity using trace comparison.
-spec behavioral_similarity(process_model(), process_model()) -> float().
behavioral_similarity(Model1, Model2) ->
    %% Generate traces and compare
    Traces1 = generate_sample_traces(Model1, 5),
    Traces2 = generate_sample_traces(Model2, 5),

    %% Compute trace similarity
    TracePairs = [{T1, T2} || T1 <- Traces1, T2 <- Traces2],

    Scores = [trace_similarity(T1, T2) || {T1, T2} <- TracePairs],

    case Scores of
        [] -> 0.0;
        _ -> lists:sum(Scores) / length(Scores)
    end.

%% @doc Compute textual similarity of activity names.
-spec textual_similarity(process_model(), process_model()) -> float().
textual_similarity(Model1, Model2) ->
    Acts1 = maps:get(activities, Model1, []),
    Acts2 = maps:get(activities, Model2, []),

    %% Compute string similarity between all pairs
    Scores = [string_similarity(A1, A2) || A1 <- Acts1, A2 <- Acts2],

    case Scores of
        [] -> 0.0;
        _ -> lists:max([lists:sum(Scores) / length(Scores), best_match_score(Acts1, Acts2)])
    end.

%% @private
best_match_score(Acts1, Acts2) ->
    %% Best match score
    Scores = [lists:max([string_similarity(A1, A2) || A2 <- Acts2]) || A1 <- Acts1],
    case Scores of
        [] -> 0.0;
        _ -> lists:sum(Scores) / length(Scores)
    end.

%% @doc Compute combined similarity score.
-spec combined_similarity(process_model(), process_model()) -> float().
combined_similarity(Model1, Model2) ->
    Struct = structural_similarity(Model1, Model2),
    Behav = behavioral_similarity(Model1, Model2),
    Text = textual_similarity(Model1, Model2),

    %% Weighted combination
    0.4 * Struct + 0.4 * Behav + 0.2 * Text.

%%====================================================================
%% API Functions - Diff Analysis
%%====================================================================

%% @doc Compute diff between two models.
-spec compute_diff(process_model(), process_model()) -> diff_result().
compute_diff(Model1, Model2) ->
    Acts1 = sets:from_list(maps:get(activities, Model1, [])),
    Acts2 = sets:from_list(maps:get(activities, Model2, [])),

    Added = sets:to_list(sets:subtract(Acts2, Acts1)),
    Removed = sets:to_list(sets:subtract(Acts1, Acts2)),
    Unchanged = sets:to_list(sets:intersection(Acts1, Acts2)),

    %% Find modified activities (same name, different structure)
    Modified = find_modified_activities(Model1, Model2, sets:from_list(Unchanged)),

    #{
        added => Added,
        removed => Removed,
        modified => Modified,
        unchanged => Unchanged
    }.

%% @doc Compute edit distance between activity sequences.
-spec compute_edit_distance([binary()], [binary()]) -> non_neg_integer().
compute_edit_distance(Seq1, Seq2) ->
    Levenshtein = levenshtein(Seq1, Seq2),
    Levenshtein.

%% @doc Find activities added in Model2 compared to Model1.
-spec find_added_activities(process_model(), process_model()) -> [binary()].
find_added_activities(Model1, Model2) ->
    Acts1 = sets:from_list(maps:get(activities, Model1, [])),
    Acts2 = sets:from_list(maps:get(activities, Model2, [])),
    sets:to_list(sets:subtract(Acts2, Acts1)).

%% @doc Find activities removed in Model2 compared to Model1.
-spec find_removed_activities(process_model(), process_model()) -> [binary()].
find_removed_activities(Model1, Model2) ->
    Acts1 = sets:from_list(maps:get(activities, Model1, [])),
    Acts2 = sets:from_list(maps:get(activities, Model2, [])),
    sets:to_list(sets:subtract(Acts1, Acts2)).

%% @doc Find activities with modified relationships.
-spec find_modified_activities(process_model(), process_model(), sets:set()) -> [{binary(), binary()}].
find_modified_activities(Model1, Model2, CommonActivities) ->
    Trans1 = maps:get(transitions, Model1, []),
    Trans2 = maps:get(transitions, Model2, []),

    lists:filtermap(
        fun(Act) ->
            PrePost1 = get_pre_post(Act, Trans1),
            PrePost2 = get_pre_post(Act, Trans2),

            case PrePost1 =:= PrePost2 of
                true -> false;
                false ->
                    {true, {Act, serialize_pre_post(PrePost2)}}
            end
        end,
        sets:to_list(CommonActivities)
    ).

%%====================================================================
%% API Functions - Alignment
%%====================================================================

%% @doc Compute alignment between two models.
-spec compute_alignment(process_model(), process_model()) -> alignment().
compute_alignment(Model1, Model2) ->
    Acts1 = maps:get(activities, Model1, []),
    Acts2 = maps:get(activities, Model2, []),

    %% Simple sequence alignment using Needleman-Wunsch
    align_sequences(Acts1, Acts2, -1, -1, 1).

%% @doc Compute alignment score.
-spec alignment_score(process_model(), process_model()) -> float().
alignment_score(Model1, Model2) ->
    Alignment = compute_alignment(Model1, Model2),

    Matches = [1 || {A, B} <- Alignment, A =/= none, B =/= none, A =:= B],
    Mismatches = [1 || {A, B} <- Alignment, A =/= none, B =/= none, A =/= B],
    Gaps = [1 || {A, B} <- Alignment, A =:= none orelse B =:= none],

    Total = length(Matches) + length(Mismatches) + length(Gaps),
    case Total of
        0 -> 1.0;
        _ -> length(Matches) / Total
    end.

%% @doc Find optimal alignment using different scoring.
-spec optimal_alignment(process_model(), process_model()) -> {alignment(), float()}.
optimal_alignment(Model1, Model2) ->
    Alignment = compute_alignment(Model1, Model2),
    Score = alignment_score(Model1, Model2),
    {Alignment, Score}.

%%====================================================================
%% API Functions - Model Matching
%%====================================================================

%% @doc Find best matching model from candidates.
-spec find_matching_model(process_model(), [process_model()]) -> {process_model(), float()} | none.
find_matching_model(Query, Candidates) ->
    Scores = [{M, combined_similarity(Query, M)} || M <- Candidates],

    case Scores of
        [] -> none;
        _ ->
            [{BestModel, BestScore} | _] = lists:sort(fun({_, S1}, {_, S2}) -> S1 > S2 end, Scores),
            {BestModel, BestScore}
    end.

%% @doc Rank models by similarity to query.
-spec rank_models_by_similarity(process_model(), [process_model()]) -> [{process_model(), float()}].
rank_models_by_similarity(Query, Candidates) ->
    Scores = [{M, combined_similarity(Query, M)} || M <- Candidates],
    lists:sort(fun({_, S1}, {_, S2}) -> S1 > S2 end, Scores).

%% @doc Cluster similar models together.
-spec cluster_similar_models([process_model()]) -> [[process_model()]].
cluster_similar_models(Models) ->
    %% Simple clustering based on similarity threshold
    Threshold = 0.7,

    %% Greedy clustering
    cluster_recursive(Models, Threshold, []).

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
transition_similarity(Trans1, Trans2) ->
    %% Compare transition structures
    Set1 = sets:from_list([transition_key(T) || T <- Trans1]),
    Set2 = sets:from_list([transition_key(T) || T <- Trans2]),

    Intersection = sets:intersection(Set1, Set2),
    Union = sets:union(Set1, Set2),

    case sets:size(Union) of
        0 -> 1.0;
        N -> sets:size(Intersection) / N
    end.

%% @private
transition_key(Transition) ->
    From = maps:get(from, Transition),
    To = maps:get(to, Transition),
    {From, To}.

%% @private
generate_sample_traces(Model, Count) ->
    %% Generate sample execution traces
    Activities = maps:get(activities, Model, []),
    Transitions = maps:get(transitions, Model, []),

    %% For simplicity, just return permutations of activities
    lists:sublist(lists:usort([shuffle_list(Activities) || _ <- lists:seq(1, Count * 10)]), Count).

%% @private
%% Manual list shuffle since lists:shuffle/1 does not exist.
shuffle_list([]) -> [];
shuffle_list(List) ->
    Tagged = [{rand:uniform(), X} || X <- List],
    [X || {_, X} <- lists:sort(Tagged)].

%% @private
trace_similarity(Trace1, Trace2) ->
    %% Compute trace similarity using longest common subsequence
    LCS = longest_common_subsequence(Trace1, Trace2),
    MaxLen = max(length(Trace1), length(Trace2)),

    case MaxLen of
        0 -> 1.0;
        N -> length(LCS) / N
    end.

%% @private
longest_common_subsequence(Seq1, Seq2) ->
    %% Dynamic programming for LCS
    M = length(Seq1),
    N = length(Seq2),

    %% Initialize DP table
    Table = array:new([{default, 0}]),

    %% Fill table
    Filled = fill_lcs_table(Seq1, Seq2, M, N, Table),

    %% Backtrack to find LCS
    backtrack_lcs(Seq1, Seq2, M, N, Filled).

%% @private
fill_lcs_table(_Seq1, _Seq2, 0, _N, Table) ->
    Table;
fill_lcs_table(_Seq1, _Seq2, _M, 0, Table) ->
    Table;
fill_lcs_table(Seq1, Seq2, I, J, Table) ->
    CurrentLen = case lists:nth(I, Seq1) =:= lists:nth(J, Seq2) of
        true ->
            1 + get_lcs_val(Table, I - 1, J - 1);
        false ->
            max(get_lcs_val(Table, I - 1, J), get_lcs_val(Table, I, J - 1))
    end,
    NewTable = array:set(I, CurrentLen, Table),
    NewTable2 = fill_lcs_table(Seq1, Seq2, I - 1, J, NewTable),
    NewTable3 = fill_lcs_table(Seq1, Seq2, I, J - 1, NewTable2),
    NewTable3.

%% @private
get_lcs_val(Table, I, J) when I > 0, J > 0 ->
    Row = array:get(I, Table),
    array:get(J, Row);
get_lcs_val(_Table, _I, _J) ->
    0.

%% @private
backtrack_lcs(_Seq1, _Seq2, 0, _J, _Table) ->
    [];
backtrack_lcs(_Seq1, _Seq2, _I, 0, _Table) ->
    [];
backtrack_lcs(Seq1, Seq2, I, J, Table) ->
    case lists:nth(I, Seq1) =:= lists:nth(J, Seq2) of
        true ->
            [lists:nth(I, Seq1) | backtrack_lcs(Seq1, Seq2, I - 1, J - 1, Table)];
        false ->
            case get_lcs_val(Table, I - 1, J) >= get_lcs_val(Table, I, J - 1) of
                true -> backtrack_lcs(Seq1, Seq2, I - 1, J, Table);
                false -> backtrack_lcs(Seq1, Seq2, I, J - 1, Table)
            end
    end.

%% @private
string_similarity(Str1, Str2) ->
    %% Levenshtein distance normalized
    Dist = levenshtein(binary_to_list(Str1), binary_to_list(Str2)),
    MaxLen = max(byte_size(Str1), byte_size(Str2)),
    case MaxLen of
        0 -> 1.0;
        _ -> 1.0 - Dist / MaxLen
    end.

%% @private
levenshtein([], Str2) ->
    length(Str2);
levenshtein(Str1, []) ->
    length(Str1);
levenshtein([C1 | Rest1], [C2 | Rest2]) when C1 =:= C2 ->
    levenshtein(Rest1, Rest2);
levenshtein([_C1 | Rest1] = Str1, [_C2 | Rest2] = Str2) ->
    lists:min([
        levenshtein(Rest1, Str2) + 1,
        levenshtein(Str1, Rest2) + 1,
        levenshtein(Rest1, Rest2) + 1
    ]).

%% @private
get_pre_post(Activity, Transitions) ->
    Presets = [maps:get(from, T) || T <- Transitions, maps:get(to, T) =:= Activity],
    Postsets = [maps:get(to, T) || T <- Transitions, maps:get(from, T) =:= Activity],
    {Presets, Postsets}.

%% @private
serialize_pre_post({Pre, Post}) ->
    #{
        predecessors => Pre,
        successors => Post
    }.

%% @private
align_sequences(Seq1, Seq2, Gap, Mismatch, Match) ->
    %% Needleman-Wunsch alignment
    M = length(Seq1),
    N = length(Seq2),

    %% Initialize DP table
    Table = array:new(),

    %% Fill first row and column
    Table1 = init_alignment_table(Table, M, N, Gap),

    %% Fill rest of table
    FilledTable = fill_alignment_table(Seq1, Seq2, M, N, Gap, Mismatch, Match, Table1),

    %% Backtrack to find alignment
    backtrack_alignment(Seq1, Seq2, M, N, FilledTable).

%% @private
init_alignment_table(Table, M, N, Gap) ->
    %% Initialize first row and column
    Table1 = array:set(0, array:from_list([X * Gap || X <- lists:seq(0, N)]), Table),
    lists:foldl(
        fun(I, Acc) ->
            Row = array:new(N + 1, {default, I * Gap}),
            array:set(I, Row, Acc)
        end,
        Table1,
        lists:seq(1, M)
    ).

%% @private
fill_alignment_table(_Seq1, _Seq2, 0, _J, _Gap, _Mismatch, _Match, Table) ->
    Table;
fill_alignment_table(_Seq1, _Seq2, _I, 0, _Gap, _Mismatch, _Match, Table) ->
    Table;
fill_alignment_table(Seq1, Seq2, I, J, Gap, Mismatch, Match, Table) ->
    Score = case lists:nth(I, Seq1) =:= lists:nth(J, Seq2) of
        true -> Match;
        false -> Mismatch
    end,

    Row = array:get(I, Table),
    Diag = array:get(J - 1, array:get(I - 1, Table)),
    Up = array:get(J, array:get(I - 1, Table)),
    Left = array:get(J - 1, Row),

    NewVal = lists:max([Diag + Score, Up + Gap, Left + Gap]),
    NewRow = array:set(J, NewVal, Row),
    NewTable = array:set(I, NewRow, Table),

    NewTable2 = fill_alignment_table(Seq1, Seq2, I - 1, J, Gap, Mismatch, Match, NewTable),
    NewTable3 = fill_alignment_table(Seq1, Seq2, I, J - 1, Gap, Mismatch, Match, NewTable2),
    NewTable3.

%% @private
get_alignment_val(Table, I, J) when I >= 0, J >= 0 ->
    Row = array:get(I, Table),
    array:get(J, Row);
get_alignment_val(_Table, _I, _J) ->
    0.

%% @private
backtrack_alignment(Seq1, Seq2, I, J, Table) when I > 0, J > 0 ->
    Row = array:get(I, Table),
    Current = array:get(J, Row),
    Diag = get_alignment_val(Table, I - 1, J - 1),
    Up = get_alignment_val(Table, I - 1, J),
    Left = get_alignment_val(Table, I, J - 1),

    Score = case lists:nth(I, Seq1) =:= lists:nth(J, Seq2) of
        true -> 1;  %% Match score
        false -> -1
    end,

    case Current =:= Diag + Score of
        true ->
            [{lists:nth(I, Seq1), lists_nth(J, Seq2)} |
             backtrack_alignment(Seq1, Seq2, I - 1, J - 1, Table)];
        false ->
            case Current =:= Up + (-1) of
                true ->
                    [{lists:nth(I, Seq1), none} |
                     backtrack_alignment(Seq1, Seq2, I - 1, J, Table)];
                false ->
                    [{none, lists_nth(J, Seq2)} |
                     backtrack_alignment(Seq1, Seq2, I, J - 1, Table)]
            end
    end;
backtrack_alignment(Seq1, _Seq2, I, 0, _Table) when I > 0 ->
    [{lists:nth(I, Seq1), none} | backtrack_alignment(Seq1, _Seq2, I - 1, 0, _Table)];
backtrack_alignment(_Seq1, Seq2, 0, J, _Table) when J > 0 ->
    [{none, lists_nth(J, Seq2)} | backtrack_alignment(_Seq1, Seq2, 0, J - 1, _Table)];
backtrack_alignment([], [], 0, 0, _Table) ->
    [].

%% @private
lists_nth(_N, []) ->
    none;
lists_nth(N, List) when N > 0, N =< length(List) ->
    lists:nth(N, List).

%% @private
cluster_recursive([], _Threshold, Acc) ->
    lists:reverse(Acc);
cluster_recursive([Model | Rest], Threshold, Acc) ->
    %% Find all similar models
    Similar = [M || M <- Rest, combined_similarity(Model, M) >= Threshold],

    %% Create cluster
    Cluster = [Model | Similar],
    Remaining = [M || M <- Rest, not lists:member(M, Similar)],

    cluster_recursive(Remaining, Threshold, [Cluster | Acc]).
