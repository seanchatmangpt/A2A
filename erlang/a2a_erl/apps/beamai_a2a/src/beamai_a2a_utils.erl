%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A Utility Functions
%%%
%%% Provides common utility functions used across the BeamAI A2A
%%% framework: UUID generation, ISO 8601 timestamps, and map
%%% manipulation helpers.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_utils).

%% API
-export([
    generate_id/0,
    now_iso8601/0,
    now_ms/0,
    deep_merge/2,
    to_binary/1,
    optional/2,
    optional/3
]).

%%--------------------------------------------------------------------
%% @doc Generate a v4-style UUID as a lowercase hex binary with dashes.
%%
%% Uses crypto:strong_rand_bytes/1 for randomness. The result follows
%% the 8-4-4-4-12 grouping convention (e.g.,
%% <<"550e8400-e29b-41d4-a716-446655440000">>).
%% @end
%%--------------------------------------------------------------------
-spec generate_id() -> binary().
generate_id() ->
    Bytes = crypto:strong_rand_bytes(16),
    %% Set version 4 (bits 48-51) and variant 1 (bits 64-65)
    <<A:4/binary, _:4, B:12, _:2, C:62>> = Bytes,
    Patched = <<A/binary, 4:4, B:12, 2:2, C:62>>,
    Hex = binary:encode_hex(Patched, lowercase),
    <<P1:8/binary, P2:4/binary, P3:4/binary, P4:4/binary, P5:12/binary>> = Hex,
    <<P1/binary, "-", P2/binary, "-", P3/binary, "-", P4/binary, "-", P5/binary>>.

%%--------------------------------------------------------------------
%% @doc Return the current UTC time as an ISO 8601 binary string.
%%
%% Format: <<"2024-01-15T12:30:45.123Z">>
%% @end
%%--------------------------------------------------------------------
-spec now_iso8601() -> binary().
now_iso8601() ->
    timestamp_to_iso8601(erlang:system_time(millisecond)).

%%--------------------------------------------------------------------
%% @doc Return the current time in milliseconds since Unix epoch.
%% @end
%%--------------------------------------------------------------------
-spec now_ms() -> integer().
now_ms() ->
    erlang:system_time(millisecond).

%%--------------------------------------------------------------------
%% @doc Deep-merge two maps recursively.
%%
%% When both values for a key are maps, they are merged recursively.
%% Otherwise the value from `Override' takes precedence.
%%
%% Example:
%%   deep_merge(#{a => #{b => 1, c => 2}}, #{a => #{c => 3}})
%%   => #{a => #{b => 1, c => 3}}
%% @end
%%--------------------------------------------------------------------
-spec deep_merge(map(), map()) -> map().
deep_merge(Base, Override) when is_map(Base), is_map(Override) ->
    maps:fold(
        fun(Key, OverrideVal, Acc) ->
            case maps:find(Key, Acc) of
                {ok, BaseVal} when is_map(BaseVal), is_map(OverrideVal) ->
                    maps:put(Key, deep_merge(BaseVal, OverrideVal), Acc);
                _ ->
                    maps:put(Key, OverrideVal, Acc)
            end
        end,
        Base,
        Override
    );
deep_merge(_Base, Override) ->
    Override.

%%--------------------------------------------------------------------
%% @doc Convert a term to binary for safe embedding in JSON or logs.
%% @end
%%--------------------------------------------------------------------
-spec to_binary(term()) -> binary().
to_binary(V) when is_binary(V) -> V;
to_binary(V) when is_list(V) -> list_to_binary(V);
to_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
to_binary(V) when is_integer(V) -> integer_to_binary(V);
to_binary(V) when is_float(V) -> float_to_binary(V, [{decimals, 6}, compact]);
to_binary(V) -> iolist_to_binary(io_lib:format("~p", [V])).

%%--------------------------------------------------------------------
%% @doc Conditionally include a key in a map when the value is not
%% `undefined'.  Returns the map unchanged if `Value' is `undefined'.
%% @end
%%--------------------------------------------------------------------
-spec optional(map(), {term(), term()}) -> map().
optional(Map, {_Key, undefined}) ->
    Map;
optional(Map, {Key, Value}) ->
    maps:put(Key, Value, Map).

%%--------------------------------------------------------------------
%% @doc Conditionally include a key in a map, using a `Default' for
%% comparison.  If `Value =:= Default', the key is omitted.
%% @end
%%--------------------------------------------------------------------
-spec optional(map(), {term(), term()}, term()) -> map().
optional(Map, {_Key, Value}, Default) when Value =:= Default ->
    Map;
optional(Map, {Key, Value}, _Default) ->
    maps:put(Key, Value, Map).

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Convert a millisecond timestamp to an ISO 8601 binary.
-spec timestamp_to_iso8601(integer()) -> binary().
timestamp_to_iso8601(TimestampMs) ->
    Seconds = TimestampMs div 1000,
    Millis = TimestampMs rem 1000,
    {{Year, Month, Day}, {Hour, Min, Sec}} =
        calendar:system_time_to_universal_time(Seconds, second),
    iolist_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~3..0BZ",
        [Year, Month, Day, Hour, Min, Sec, Millis]
    )).
