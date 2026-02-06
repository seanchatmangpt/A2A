%%%-------------------------------------------------------------------
%%% @doc BeamAI Output Parser.
%%%
%%% Provides structured extraction from LLM text responses.
%%% Supports:
%%% - JSON extraction (from code blocks or raw text)
%%% - XML extraction and parsing
%%% - CSV extraction and parsing
%%% - Custom regex/pattern extraction
%%% - Retry wrapper for re-prompting on parse failure
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_output_parser).

-export([
    parse_json/1,
    parse_json/2,
    parse_xml/1,
    parse_xml/2,
    parse_csv/1,
    parse_csv/2,
    parse_pattern/2,
    parse_pattern/3,
    with_retry/2,
    with_retry/3,
    extract_code_block/1,
    extract_code_block/2
]).

%%====================================================================
%% Type Definitions
%%====================================================================

-type parse_opts() :: #{
    strict => boolean(),
    default => term(),
    transform => fun((term()) -> term())
}.

-type retry_opts() :: #{
    max_retries => non_neg_integer(),
    retry_prompt => binary(),
    provider => atom(),
    model => binary()
}.

-export_type([parse_opts/0, retry_opts/0]).

%%====================================================================
%% JSON Parsing
%%====================================================================

%% @doc Extract and parse JSON from LLM response text.
%% Handles JSON in code blocks, bare JSON objects, and arrays.
-spec parse_json(binary()) -> {ok, map() | list()} | {error, term()}.
parse_json(Text) ->
    parse_json(Text, #{}).

%% @doc Parse JSON with options.
%% Options:
%%   strict    - If true, fail on non-JSON content (default false)
%%   default   - Default value if parse fails
%%   transform - Function to apply to parsed result
-spec parse_json(binary(), parse_opts()) -> {ok, map() | list()} | {error, term()}.
parse_json(Text, Opts) ->
    Result = try_parse_json(Text),
    apply_opts(Result, Opts).

%%====================================================================
%% XML Parsing
%%====================================================================

%% @doc Extract and parse XML from LLM response text.
-spec parse_xml(binary()) -> {ok, term()} | {error, term()}.
parse_xml(Text) ->
    parse_xml(Text, #{}).

%% @doc Parse XML with options.
-spec parse_xml(binary(), parse_opts()) -> {ok, term()} | {error, term()}.
parse_xml(Text, Opts) ->
    Result = try_parse_xml(Text),
    apply_opts(Result, Opts).

%%====================================================================
%% CSV Parsing
%%====================================================================

%% @doc Extract and parse CSV from LLM response text.
%% Returns a list of rows, where each row is a list of fields.
-spec parse_csv(binary()) -> {ok, [[binary()]]} | {error, term()}.
parse_csv(Text) ->
    parse_csv(Text, #{}).

%% @doc Parse CSV with options.
%% Options (in addition to standard parse_opts):
%%   delimiter  - Field delimiter (default comma)
%%   has_header - Whether first row is header (default true)
-spec parse_csv(binary(), map()) -> {ok, [[binary()]] | [map()]} | {error, term()}.
parse_csv(Text, Opts) ->
    Delimiter = maps:get(delimiter, Opts, <<",">>),
    HasHeader = maps:get(has_header, Opts, true),
    Result = try_parse_csv(Text, Delimiter, HasHeader),
    apply_opts(Result, Opts).

%%====================================================================
%% Pattern Extraction
%%====================================================================

%% @doc Extract content matching a regex pattern from LLM response.
-spec parse_pattern(binary(), binary()) ->
    {ok, [binary()]} | {error, term()}.
parse_pattern(Text, Pattern) ->
    parse_pattern(Text, Pattern, #{}).

%% @doc Extract content matching a pattern with options.
%% Options:
%%   capture - Which capture groups to return (default all)
%%   global  - Return all matches (default false)
-spec parse_pattern(binary(), binary(), map()) ->
    {ok, [binary()]} | {error, term()}.
parse_pattern(Text, Pattern, Opts) ->
    Global = maps:get(global, Opts, false),
    try
        ReOpts = case Global of
            true -> [global, {capture, all, binary}];
            false -> [{capture, all, binary}]
        end,
        case re:run(Text, Pattern, ReOpts) of
            {match, Captures} ->
                Flattened = flatten_captures(Captures),
                apply_opts({ok, Flattened}, Opts);
            nomatch ->
                apply_opts({error, no_match}, Opts)
        end
    catch
        _:Error ->
            apply_opts({error, {regex_error, Error}}, Opts)
    end.

%%====================================================================
%% Retry Wrapper
%%====================================================================

%% @doc Wrap a parse function with retry logic.
%% If parsing fails, re-prompts the LLM asking for properly formatted output.
-spec with_retry(fun(), binary()) ->
    {ok, term()} | {error, term()}.
with_retry(ParseFun, OriginalResponse) ->
    with_retry(ParseFun, OriginalResponse, #{}).

%% @doc Retry with options.
%% Options:
%%   max_retries  - Number of retry attempts (default 2)
%%   retry_prompt - Custom prompt for retry (default: format correction)
%%   provider     - LLM provider for re-prompting
-spec with_retry(fun(), binary(), retry_opts()) ->
    {ok, term()} | {error, term()}.
with_retry(ParseFun, OriginalResponse, Opts) ->
    MaxRetries = maps:get(max_retries, Opts, 2),
    do_retry(ParseFun, OriginalResponse, 0, MaxRetries, Opts).

%%====================================================================
%% Code Block Extraction
%%====================================================================

%% @doc Extract content from the first code block in the text.
-spec extract_code_block(binary()) -> {ok, binary()} | {error, no_code_block}.
extract_code_block(Text) ->
    extract_code_block(Text, any).

%% @doc Extract content from a code block with a specific language tag.
-spec extract_code_block(binary(), atom() | binary()) ->
    {ok, binary()} | {error, no_code_block}.
extract_code_block(Text, any) ->
    Pattern = <<"```[a-zA-Z]*\\s*\\n([\\s\\S]*?)\\n\\s*```">>,
    case re:run(Text, Pattern, [{capture, [1], binary}]) of
        {match, [Content]} -> {ok, Content};
        nomatch -> {error, no_code_block}
    end;
extract_code_block(Text, Language) ->
    LangBin = ensure_binary(Language),
    Pattern = <<"```", LangBin/binary, "\\s*\\n([\\s\\S]*?)\\n\\s*```">>,
    case re:run(Text, Pattern, [{capture, [1], binary}]) of
        {match, [Content]} -> {ok, Content};
        nomatch -> {error, no_code_block}
    end.

%%====================================================================
%% Internal Functions - JSON
%%====================================================================

%% @private
try_parse_json(Text) ->
    %% Strategy 1: Try to extract from code block
    case extract_code_block(Text, json) of
        {ok, JsonBlock} ->
            try_decode_json(JsonBlock);
        {error, _} ->
            %% Strategy 2: Try from any code block
            case extract_code_block(Text) of
                {ok, Block} ->
                    case try_decode_json(Block) of
                        {ok, _} = R -> R;
                        {error, _} -> try_extract_bare_json(Text)
                    end;
                {error, _} ->
                    %% Strategy 3: Try bare JSON
                    try_extract_bare_json(Text)
            end
    end.

%% @private
try_extract_bare_json(Text) ->
    %% Try to find JSON object
    case re:run(Text, <<"(\\{[\\s\\S]*\\})">>, [{capture, [1], binary}]) of
        {match, [JsonStr]} ->
            case try_decode_json(JsonStr) of
                {ok, _} = R -> R;
                {error, _} -> try_extract_json_array(Text)
            end;
        nomatch ->
            try_extract_json_array(Text)
    end.

%% @private
try_extract_json_array(Text) ->
    case re:run(Text, <<"(\\[[\\s\\S]*\\])">>, [{capture, [1], binary}]) of
        {match, [JsonStr]} ->
            try_decode_json(JsonStr);
        nomatch ->
            {error, no_json_found}
    end.

%% @private
try_decode_json(Str) ->
    try
        Decoded = jsx:decode(Str, [return_maps]),
        {ok, Decoded}
    catch
        _:_ -> {error, {invalid_json, Str}}
    end.

%%====================================================================
%% Internal Functions - XML
%%====================================================================

%% @private
try_parse_xml(Text) ->
    %% Try to extract from code block first
    XmlText = case extract_code_block(Text, xml) of
        {ok, Block} -> Block;
        {error, _} ->
            %% Try to find XML content directly
            case re:run(Text, <<"(<[a-zA-Z][\\s\\S]*>)">>, [{capture, [1], binary}]) of
                {match, [XmlStr]} -> XmlStr;
                nomatch -> Text
            end
    end,
    %% Parse using xmerl
    try
        {Doc, _} = xmerl_scan:string(binary_to_list(XmlText)),
        Simplified = simplify_xml(Doc),
        {ok, Simplified}
    catch
        _:Error ->
            {error, {xml_parse_error, Error}}
    end.

%% @private
%% Simplify xmerl output into maps.
simplify_xml(Element) when is_tuple(Element) ->
    case element(1, Element) of
        xmlElement ->
            Name = element(2, Element),
            Children = element(9, Element),
            SimplifiedChildren = [simplify_xml(C) || C <- Children,
                                  is_tuple(C), (element(1, C) =:= xmlElement orelse
                                                element(1, C) =:= xmlText)],
            #{
                tag => atom_to_binary(Name, utf8),
                children => SimplifiedChildren
            };
        xmlText ->
            Value = element(4, Element),
            Trimmed = string:trim(Value),
            case Trimmed of
                "" -> #{text => <<>>};
                _ -> #{text => list_to_binary(Trimmed)}
            end;
        _ ->
            #{unknown => Element}
    end;
simplify_xml(Other) ->
    #{raw => Other}.

%%====================================================================
%% Internal Functions - CSV
%%====================================================================

%% @private
try_parse_csv(Text, Delimiter, HasHeader) ->
    %% Try to extract from code block first
    CsvText = case extract_code_block(Text, csv) of
        {ok, Block} -> Block;
        {error, _} -> Text
    end,
    try
        Lines = binary:split(CsvText, [<<"\n">>, <<"\r\n">>], [global, trim_all]),
        NonEmptyLines = [L || L <- Lines, byte_size(string:trim(L)) > 0],
        Rows = [parse_csv_line(Line, Delimiter) || Line <- NonEmptyLines],
        case {HasHeader, Rows} of
            {true, [Header | DataRows]} ->
                Maps = [csv_row_to_map(Header, Row) || Row <- DataRows],
                {ok, Maps};
            {false, _} ->
                {ok, Rows};
            {true, []} ->
                {ok, []}
        end
    catch
        _:Error ->
            {error, {csv_parse_error, Error}}
    end.

%% @private
parse_csv_line(Line, Delimiter) ->
    %% Simple CSV parsing (does not handle quoted fields with delimiters)
    Fields = binary:split(Line, Delimiter, [global]),
    [string:trim(F) || F <- Fields].

%% @private
csv_row_to_map(Header, Row) ->
    Pairs = lists:zip(Header, pad_row(Row, length(Header))),
    maps:from_list(Pairs).

%% @private
pad_row(Row, TargetLen) when length(Row) >= TargetLen ->
    lists:sublist(Row, TargetLen);
pad_row(Row, TargetLen) ->
    Row ++ lists:duplicate(TargetLen - length(Row), <<>>).

%%====================================================================
%% Internal Functions - Retry
%%====================================================================

%% @private
do_retry(ParseFun, Response, Attempt, MaxRetries, _Opts) when Attempt > MaxRetries ->
    %% Final attempt: try parsing one last time
    ParseFun(Response);
do_retry(ParseFun, Response, 0, MaxRetries, Opts) ->
    %% First attempt
    case ParseFun(Response) of
        {ok, _} = Success ->
            Success;
        {error, _Reason} when MaxRetries > 0 ->
            %% Re-prompt the LLM
            RetryPrompt = maps:get(retry_prompt, Opts,
                <<"Your previous response could not be parsed. "
                  "Please respond again with properly formatted output. "
                  "Use valid JSON, XML, or the requested format.">>),
            Provider = maps:get(provider, Opts, anthropic),
            Messages = [
                #{role => <<"assistant">>, content => Response},
                #{role => <<"user">>, content => RetryPrompt}
            ],
            case beamai_chat_completion:complete(Provider, Messages, Opts) of
                {ok, #{text := NewResponse}} ->
                    do_retry(ParseFun, NewResponse, 1, MaxRetries, Opts);
                {ok, #{content := NewResponse}} when is_binary(NewResponse) ->
                    do_retry(ParseFun, NewResponse, 1, MaxRetries, Opts);
                {error, _} = Err ->
                    Err
            end;
        {error, _} = Err ->
            Err
    end;
do_retry(ParseFun, Response, Attempt, MaxRetries, Opts) ->
    case ParseFun(Response) of
        {ok, _} = Success ->
            Success;
        {error, _} ->
            do_retry(ParseFun, Response, Attempt + 1, MaxRetries, Opts)
    end.

%%====================================================================
%% Internal Functions - Common
%%====================================================================

%% @private
apply_opts({ok, Value}, Opts) ->
    case maps:get(transform, Opts, undefined) of
        undefined -> {ok, Value};
        TransformFun ->
            try
                {ok, TransformFun(Value)}
            catch
                _:Error -> {error, {transform_error, Error}}
            end
    end;
apply_opts({error, _Reason}, Opts) ->
    case maps:get(default, Opts, undefined) of
        undefined ->
            case maps:get(strict, Opts, false) of
                true -> {error, _Reason};
                false -> {error, _Reason}
            end;
        Default ->
            {ok, Default}
    end.

%% @private
flatten_captures(Captures) when is_list(Captures) ->
    case Captures of
        [First | _] when is_list(First) ->
            %% Global match returns list of lists
            lists:flatmap(fun(C) -> C end, Captures);
        _ ->
            Captures
    end;
flatten_captures(Other) ->
    [Other].

%% @private
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V).
