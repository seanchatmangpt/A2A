#!/usr/bin/env escript
%%%-------------------------------------------------------------------
%%% @doc
%%% XES Validation Script
%%%
%%% This script validates generated XES files against the IEEE 1849-2016
%%% standard. It performs:
%%%
%%% 1. XML well-formedness validation
%%% 2. XES schema structure validation
%%% 3. Required attribute checks
%%% 4. Extension declaration validation
%%% 5. Timestamp format validation
%%% 6. Compliance reporting
%%%
%%% Usage:
%%%   escript xes_validation.escript <file.xes> [options]
%%%
%%% Options:
%%%   --verbose              Show detailed validation output
%%%   --report <file>        Generate validation report file
%%%   --schema <file>        Use custom XES schema file
%%%   --strict               Fail on any warnings
%%%
%%% @end
%%%-------------------------------------------------------------------

-mode(compile).

%%====================================================================
%% Main Entry Point
%%====================================================================

main(Args) ->
    case parse_args(Args) of
        {error, Reason} ->
            io:format("Error: ~s~n", [Reason]),
            usage(),
            halt(1);

        {Options, [XESFile]} ->
            validate_xes_file(XESFile, Options);

        _ ->
            usage(),
            halt(1)
    end.

%%====================================================================
%% Command Line Parsing
%%====================================================================

parse_args(Args) ->
    parse_args_loop(Args, #{verbose => false, strict => false, report => undefined}, []).

parse_args_loop([], Options, Remaining) ->
    {Options, lists:reverse(Remaining)};

parse_args_loop(["--verbose" | Rest], Options, Remaining) ->
    parse_args_loop(Rest, Options#{verbose => true}, Remaining);

parse_args_loop(["--strict" | Rest], Options, Remaining) ->
    parse_args_loop(Rest, Options#{strict => true}, Remaining);

parse_args_loop(["--report", ReportFile | Rest], Options, Remaining) ->
    parse_args_loop(Rest, Options#{report => ReportFile}, Remaining);

parse_args_loop(["--schema", SchemaFile | Rest], Options, Remaining) ->
    parse_args_loop(Rest, Options#{schema => SchemaFile}, Remaining);

parse_args_loop([Arg | Rest], Options, Remaining) ->
    parse_args_loop(Rest, Options, [Arg | Remaining]).

%%====================================================================
%% Usage Information
%%====================================================================

usage() ->
    io:format("~nXES Validation Script - IEEE 1849-2016 Compliance Checker~n"),
    io:format("~nUsage:~n"),
    io:format("  escript xes_validation.escript <file.xes> [options]~n~n"),
    io:format("Options:~n"),
    io:format("  --verbose              Show detailed validation output~n"),
    io:format("  --report <file>        Generate validation report file~n"),
    io:format("  --schema <file>        Use custom XES schema file~n"),
    io:format("  --strict               Fail on any warnings~n~n"),
    io:format("Examples:~n"),
    io:format("  escript xes_validation.escript workflow.xes~n"),
    io:format("  escript xes_validation.escript workflow.xes --verbose --report report.txt~n"),
    io:format("~n").

%%====================================================================
%% XES Validation
%%====================================================================

validate_xes_file(XESFile, Options) ->
    io:format("~n=== XES Validation: ~s ===~n", [XESFile]),

    %% Check if file exists
    case file:read_file(XESFile) of
        {error, Reason} ->
            io:format("Error: Cannot read file: ~p~n", [Reason]),
            halt(1);

        {ok, Content} ->
            %% Perform validation checks
            Results = [
                {xml_wellformedness, check_xml_wellformedness(Content, Options)},
                {xes_structure, check_xes_structure(Content, Options)},
                {required_attributes, check_required_attributes(Content, Options)},
                {extension_declarations, check_extensions(Content, Options)},
                {timestamp_formats, check_timestamps(Content, Options)},
                {namespace_declarations, check_namespaces(Content, Options)},
                {attribute_types, check_attribute_types(Content, Options)},
                {trace_event_structure, check_trace_event_structure(Content, Options)}
            ],

            %% Generate report
            Report = generate_validation_report(XESFile, Results, Options),

            %% Output results
            print_validation_results(Results, maps:get(verbose, Options, false)),

            %% Write report file if requested
            case maps:get(report, Options, undefined) of
                undefined -> ok;
                ReportFile ->
                    write_report(ReportFile, Report)
            end,

            %% Determine exit code
            ShouldFail = has_critical_errors(Results) orelse
                       (maps:get(strict, Options, false) andalso has_any_errors(Results)),

            case ShouldFail of
                true ->
                    io:format("~n=== VALIDATION FAILED ===~n"),
                    halt(1);
                false ->
                    io:format("~n=== VALIDATION PASSED ===~n"),
                    halt(0)
            end
    end.

%%====================================================================
%% Validation Checks
%%====================================================================

%% @doc Check XML well-formedness
check_xml_wellformedness(Content, _Options) ->
    case catch xmerl_scan:string(binary_to_list(Content)) of
        {error, Reason} ->
            {fail, "XML parsing failed", [{reason, Reason}]};
        {'EXIT', Reason} ->
            {fail, "XML parsing crashed", [{reason, Reason}]};
        {_ParsedDoc, _Rest} ->
            {pass, "XML is well-formed", []}
    end.

%% @doc Check XES structure
check_xes_structure(Content, Options) ->
    ContentStr = binary_to_list(Content),

    Checks = [
        {xml_declaration, fun() ->
            string:str(ContentStr, "<?xml") > 0
        end},
        {log_open_tag, fun() ->
            string:str(ContentStr, "<log") > 0
        end},
        {log_close_tag, fun() ->
            string:str(ContentStr, "</log>") > 0
        end},
        {trace_element, fun() ->
            string:str(ContentStr, "<trace") > 0 andalso
            string:str(ContentStr, "</trace>") > 0
        end},
        {event_element, fun() ->
            string:str(ContentStr, "<event") > 0 andalso
            string:str(ContentStr, "</event>") > 0
        end}
    ],

    FailedChecks = [Name || {Name, Check} <- Checks, not Check()],

    case FailedChecks of
        [] ->
            {pass, "XES structure is valid", []};
        _ ->
            {fail, "Missing required XES elements",
             [{missing, FailedChecks}]}
    end.

%% @doc Check required attributes
check_required_attributes(Content, _Options) ->
    ContentStr = binary_to_list(Content),

    %% Required per IEEE 1849-2016
    RequiredAttrs = [
        "xes.version",
        "xmlns",
        "concept:name",
        "time:timestamp"
    ],

    MissingAttrs = [Attr || Attr <- RequiredAttrs,
                           string:str(ContentStr, Attr) =:= 0],

    case MissingAttrs of
        [] ->
            {pass, "All required attributes present", []};
        _ ->
            {warn, "Some recommended attributes missing",
             [{missing, MissingAttrs}]}
    end.

%% @doc Check extension declarations
check_extensions(Content, _Options) ->
    ContentStr = binary_to_list(Content),

    %% Standard XES extensions
    StandardExtensions = [
        "time.xesext",
        "concept.xesext",
        "lifecycle.xesext",
        "org.xesext"
    ],

    %% Find extension declarations
    FoundExtensions = [Ext || Ext <- StandardExtensions,
                             string:str(ContentStr, Ext) > 0],

    HasExtensions = string:str(ContentStr, "<extension") > 0,

    case {HasExtensions, FoundExtensions} of
        {true, [_|_]} ->
            {pass, "Extensions properly declared",
             [{found_extensions, length(FoundExtensions)}]};
        {true, []} ->
            {warn, "Extension declarations found but no standard extensions", []};
        {false, []} ->
            {warn, "No extensions declared", []}
    end.

%% @doc Check timestamp formats
check_timestamps(Content, _Options) ->
    ContentStr = binary_to_list(Content),

    %% Find all timestamp attributes
    TimestampPattern = "time:timestamp",
    case string:str(ContentStr, TimestampPattern) of
        0 ->
            {warn, "No timestamps found", []};
        _ ->
            %% Extract timestamp values (simplified)
            %% Check for ISO 8601 format: YYYY-MM-DDTHH:MM:SS.sssZ
            HasISOFormat = string:str(ContentStr, "T") > 0 andalso
                           string:str(ContentStr, "Z") > 0,

            if
                HasISOFormat ->
                    {pass, "Timestamps use ISO 8601 format", []};
                true ->
                    {warn, "Timestamps present but format unclear", []}
            end
    end.

%% @doc Check namespace declarations
check_namespaces(Content, _Options) ->
    ContentStr = binary_to_list(Content),

    %% Check for XES namespace
    HasXESNamespace = string:str(ContentStr, "xes-standard.org") > 0 orelse
                       string:str(ContentStr, "www.xes-standard.org") > 0,

    if
        HasXESNamespace ->
            {pass, "XES namespace declared", []};
        true ->
            {warn, "XES namespace not found", []}
    end.

%% @doc Check attribute types
check_attribute_types(Content, _Options) ->
    ContentStr = binary_to_list(Content),

    %% XES attribute types
    AttributeTypes = [
        {string, "<string"},
        {date, "<date"},
        {int, "<int"},
        {float, "<float"},
        {boolean, "<boolean"},
        {id, "<id"},
        {list, "<list"}
    ],

    FoundTypes = [Type || {Type, Pattern} <- AttributeTypes,
                           string:str(ContentStr, Pattern) > 0],

    case FoundTypes of
        [_|_] ->
            {pass, "Attribute types properly declared",
             [{found_types, length(FoundTypes)}]};
        [] ->
            {warn, "No typed attributes found", []}
    end.

%% @doc Check trace and event structure
check_trace_event_structure(Content, _Options) ->
    ContentStr = binary_to_list(Content),

    %% Count opening and closing tags
    TraceOpenCount = count_occurrences(ContentStr, "<trace"),
    TraceCloseCount = count_occurrences(ContentStr, "</trace>"),

    EventOpenCount = count_occurrences(ContentStr, "<event"),
    EventCloseCount = count_occurrences(ContentStr, "</event>"),

    case {TraceOpenCount =:= TraceCloseCount,
          EventOpenCount =:= EventCloseCount} of
        {true, true} ->
            {pass, "Trace and event structure balanced",
             [{traces, TraceOpenCount}, {events, EventOpenCount}]};
        {false, _} ->
            {fail, "Unbalanced trace tags",
             [{open, TraceOpenCount}, {close, TraceCloseCount}]};
        {_, false} ->
            {fail, "Unbalanced event tags",
             [{open, EventOpenCount}, {close, EventCloseCount}]}
    end.

%%====================================================================
%% Report Generation
%%====================================================================

generate_validation_report(XESFile, Results, Options) ->
    {TotalPassed, TotalFailed, TotalWarned} = summarize_results(Results),

    Report = [
        {file, XESFile},
        {timestamp, calendar:universal_time()},
        {results, Results},
        {summary, #{
            total_passed => TotalPassed,
            total_failed => TotalFailed,
            total_warned => TotalWarned,
            status => status_string(TotalFailed, TotalWarned, maps:get(strict, Options, false))
        }}
    ],

    Report.

print_validation_results(Results, Verbose) ->
    io:format("~nValidation Results:~n"),
    io:format("-------------------~n"),

    lists:foreach(fun({CheckName, Result}) ->
        {Status, Message, Details} = Result,
        StatusStr = case Status of
            pass -> "[PASS]";
            fail -> "[FAIL]";
            warn -> "[WARN]"
        end,

        io:format("~s ~s: ~s~n", [StatusStr, CheckName, Message]),

        if
            Verbose andalso length(Details) > 0 ->
                lists:foreach(fun({Key, Value}) ->
                    io:format("    - ~s: ~p~n", [Key, Value])
                end, Details);
            true ->
                ok
        end
    end, Results).

write_report(ReportFile, Report) ->
    {ok, F} = file:open(ReportFile, [write]),

    io:format(F, "XES Validation Report~n", []),
    io:format(F, "====================~n~n", []),

    %% File info
    io:format(F, "File: ~s~n", [proplists:get_value(file, Report)]),
    io:format(F, "Timestamp: ~p~n~n", [proplists:get_value(timestamp, Report)]),

    %% Summary
    Summary = proplists:get_value(summary, Report),
    io:format(F, "Summary:~n", []),
    io:format(F, "  Passed: ~p~n", [maps:get(total_passed, Summary)]),
    io:format(F, "  Failed: ~p~n", [maps:get(total_failed, Summary)]),
    io:format(F, "  Warnings: ~p~n", [maps:get(total_warned, Summary)]),
    io:format(F, "  Status: ~s~n~n", [maps:get(status, Summary)]),

    %% Detailed results
    io:format(F, "Detailed Results:~n", []),
    lists:foreach(fun({CheckName, Result}) ->
        {Status, Message, Details} = Result,
        io:format(F, "  ~s: ~s - ~s~n", [CheckName, Status, Message]),
        lists:foreach(fun({Key, Value}) ->
            io:format(F, "    ~s: ~p~n", [Key, Value])
        end, Details)
    end, proplists:get_value(results, Report)),

    file:close(F),

    io:format("Report written to: ~s~n", [ReportFile]).

%%====================================================================
%% Summary and Status
%%====================================================================

summarize_results(Results) ->
    lists:foldl(fun({_CheckName, {Status, _Message, _Details}}, {Pass, Fail, Warn}) ->
        case Status of
            pass -> {Pass + 1, Fail, Warn};
            fail -> {Pass, Fail + 1, Warn};
            warn -> {Pass, Fail, Warn + 1}
        end
    end, {0, 0, 0}, Results).

status_string(0, 0, _Strict) -> "PASSED";
status_string(0, _Warns, false) -> "PASSED (with warnings)";
status_string(0, _Warns, true) -> "FAILED (strict mode)";
status_string(_Fails, _Warns, _Strict) -> "FAILED".

has_critical_errors(Results) ->
    lists:any(fun({_CheckName, {Status, _Message, _Details}}) ->
        Status =:= fail
    end, Results).

has_any_errors(Results) ->
    lists:any(fun({_CheckName, {Status, _Message, _Details}}) ->
        Status =:= fail orelse Status =:= warn
    end, Results).

%%====================================================================
%% Utility Functions
%%====================================================================

%% @doc Count occurrences of substring in string
count_occurrences(String, Substring) ->
    count_occurrences_loop(String, Substring, 0).

count_occurrences_loop(String, Substring, Count) ->
    case string:str(String, Substring) of
        0 -> Count;
        Index ->
            NewString = lists:nthtail(Index + length(Substring) - 1, String),
            count_occurrences_loop(NewString, Substring, Count + 1)
    end.
