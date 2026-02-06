%%%-------------------------------------------------------------------
%%% @doc BeamAI Template rendering utility.
%%% Provides simple template rendering with variable substitution.
%%% Templates use {{variable_name}} syntax for placeholders.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_template).

-export([
    render/2,
    render_file/2,
    compile/1
]).

-type template() :: binary().
-type bindings() :: map().
-type compiled_template() :: [binary() | {var, binary()}].

-export_type([template/0, bindings/0, compiled_template/0]).

%%--------------------------------------------------------------------
%% @doc Render a template string with the given bindings.
%% Replaces {{key}} placeholders with values from the bindings map.
%%
%% Example:
%%   render(<<"Hello {{name}}!">>, #{<<"name">> => <<"World">>})
%%   => <<"Hello World!">>
%% @end
%%--------------------------------------------------------------------
-spec render(template(), bindings()) -> binary().
render(Template, Bindings) ->
    Compiled = compile(Template),
    render_compiled(Compiled, Bindings).

%%--------------------------------------------------------------------
%% @doc Render a template from a file path with the given bindings.
%% @end
%%--------------------------------------------------------------------
-spec render_file(file:filename_all(), bindings()) -> {ok, binary()} | {error, term()}.
render_file(FilePath, Bindings) ->
    case file:read_file(FilePath) of
        {ok, Template} ->
            {ok, render(Template, Bindings)};
        {error, Reason} ->
            {error, {template_file_error, Reason}}
    end.

%%--------------------------------------------------------------------
%% @doc Compile a template into an intermediate representation
%% for efficient repeated rendering.
%% @end
%%--------------------------------------------------------------------
-spec compile(template()) -> compiled_template().
compile(Template) ->
    compile(Template, [], <<>>).

%%====================================================================
%% Internal functions
%%====================================================================

%% @private
-spec compile(binary(), compiled_template(), binary()) -> compiled_template().
compile(<<>>, Acc, Current) ->
    case Current of
        <<>> -> lists:reverse(Acc);
        _ -> lists:reverse([Current | Acc])
    end;
compile(<<"{{", Rest/binary>>, Acc, Current) ->
    case binary:split(Rest, <<"}}">>) of
        [VarName, Remainder] ->
            TrimmedVar = string:trim(VarName),
            NewAcc = case Current of
                <<>> -> [{var, TrimmedVar} | Acc];
                _ -> [{var, TrimmedVar}, Current | Acc]
            end,
            compile(Remainder, NewAcc, <<>>);
        _ ->
            %% No closing }}, treat as literal
            compile(Rest, Acc, <<Current/binary, "{{">>)
    end;
compile(<<C, Rest/binary>>, Acc, Current) ->
    compile(Rest, Acc, <<Current/binary, C>>).

%% @private
-spec render_compiled(compiled_template(), bindings()) -> binary().
render_compiled(Compiled, Bindings) ->
    Parts = lists:map(
        fun
            ({var, Key}) ->
                case maps:find(Key, Bindings) of
                    {ok, Value} -> to_binary(Value);
                    error ->
                        %% Try atom key
                        AtomKey = try binary_to_existing_atom(Key, utf8)
                                  catch _:_ -> undefined end,
                        case maps:find(AtomKey, Bindings) of
                            {ok, Value} -> to_binary(Value);
                            error -> <<"{{", Key/binary, "}}">>
                        end
                end;
            (Literal) when is_binary(Literal) ->
                Literal
        end,
        Compiled
    ),
    iolist_to_binary(Parts).

%% @private
-spec to_binary(term()) -> binary().
to_binary(V) when is_binary(V) -> V;
to_binary(V) when is_list(V) -> list_to_binary(V);
to_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
to_binary(V) when is_integer(V) -> integer_to_binary(V);
to_binary(V) when is_float(V) -> float_to_binary(V, [{decimals, 6}, compact]);
to_binary(V) -> iolist_to_binary(io_lib:format("~p", [V])).
