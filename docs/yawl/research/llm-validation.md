# LLM Validation

AI-assisted workflow verification using Large Language Models.

## Overview

LLM validation leverages large language models to verify workflow correctness, soundness, and completeness. This module implements the AI-assisted verification approach from van der Aalst et al. (2026).

## Capabilities

1. **Correctness**: Verify workflow executes without errors
2. **Soundness**: Check for deadlocks and livelocks
3. **Completeness**: Ensure all required paths exist
4. **Consistency**: Validate data flow consistency
5. **Comparison**: Compare two workflows for equivalence
6. **Suggestions**: Generate improvement recommendations

## Architecture

```ermaid
graph TB
    LLM[LLM Validator] --> Extractor[Workflow Extractor]
    LLM --> Prompt[Prompt Builder]
    LLM --> Client[LLM Client]
    Client --> Parser[Response Parser]

    Extractor --> Prompt
    Prompt --> Client
    Client --> Parser
    Parser --> Result[Validation Result]
```

## Implementation

### LLM Validator

```erlang
-module(yawl_llm_validator).

-export([validate/2, validate/3, compare/3, suggest_improvements/2]).

%% Main validation function
-spec validate(binary(), [atom()]) -> {ok, validation_result()} | {error, term()}.
validate(WorkflowId, Aspects) ->
    validate(WorkflowId, Aspects, #{}).

-spec validate(binary(), [atom()], map()) -> {ok, validation_result()} | {error, term()}.
validate(WorkflowId, Aspects, Options) ->
    {ok, Workflow} = workflow_store:get(WorkflowId),

    %% Extract workflow information
    WorkflowInfo = extract_workflow_info(Workflow),

    %% Build prompts for each aspect
    Results = lists:map(fun(Aspect) ->
        validate_aspect(Aspect, WorkflowInfo, Options)
    end, Aspects),

    %% Aggregate results
    OverallResult = aggregate_results(Results),

    {ok, #validation_result{
        workflow_id => WorkflowId,
        validation_id => yawl_utils:generate_id(validation),
        timestamp => erlang:system_time(millisecond),
        overall_result => OverallResult,
        aspects => maps:from_list(lists:zip(Aspects, Results)),
        suggestions => generate_suggestions(Results),
        model_info => get_model_info()
    }}.

%% Validate specific aspect
validate_aspect(correctness, Info, _Options) ->
    Prompt = build_correctness_prompt(Info),
    case call_llm(Prompt) of
        {ok, Response} ->
            parse_correctness_response(Response);
        {error, Reason} ->
            {error, Reason}
    end;

validate_aspect(soundness, Info, _Options) ->
    Prompt = build_soundness_prompt(Info),
    case call_llm(Prompt) of
        {ok, Response} ->
            parse_soundness_response(Response);
        {error, Reason} ->
            {error, Reason}
    end;

validate_aspect(completeness, Info, Options) ->
    Prompt = build_completeness_prompt(Info, Options),
    case call_llm(Prompt) of
        {ok, Response} ->
            parse_completeness_response(Response);
        {error, Reason} ->
            {error, Reason}
    end;

validate_aspect(consistency, Info, _Options) ->
    Prompt = build_consistency_prompt(Info),
    case call_llm(Prompt) of
        {ok, Response} ->
            parse_consistency_response(Response);
        {error, Reason} ->
            {error, Reason}
    end.

%% Compare two workflows
-spec compare(binary(), binary(), atom()) -> {ok, comparison_result()} | {error, term()}.
compare(WorkflowId1, WorkflowId2, ComparisonType) ->
    {ok, Workflow1} = workflow_store:get(WorkflowId1),
    {ok, Workflow2} = workflow_store:get(WorkflowId2),

    Info1 = extract_workflow_info(Workflow1),
    Info2 = extract_workflow_info(Workflow2),

    Prompt = case ComparisonType of
        equivalence ->
            build_equivalence_prompt(Info1, Info2);
        behavioral ->
            build_behavioral_comparison_prompt(Info1, Info2);
        structural ->
            build_structural_comparison_prompt(Info1, Info2)
    end,

    case call_llm(Prompt) of
        {ok, Response} ->
            {ok, parse_comparison_response(Response)};
        {error, Reason} ->
            {error, Reason}
    end.

%% Suggest improvements
-spec suggest_improvements(binary()) -> {ok, [binary()]} | {error, term()}.
suggest_improvements(WorkflowId) ->
    {ok, Workflow} = workflow_store:get(WorkflowId),
    Info = extract_workflow_info(Workflow),

    Prompt = build_suggestion_prompt(Info),

    case call_llm(Prompt) of
        {ok, Response} ->
            Suggestions = parse_suggestions(Response),
            {ok, Suggestions};
        {error, Reason} ->
            {error, Reason}
    end.

%% Extract workflow information for LLM
extract_workflow_info(Workflow) ->
    #{
        pattern => Workflow#workflow.pattern_type,
        steps => Workflow#workflow.steps,
        transitions => Workflow#workflow.transitions,
        places => Workflow#workflow.places,
        variables => Workflow#workflow.variables,
        handlers => Workflow#workflow.handlers,
        description => Workflow#workflow.description
    }.

%% Call LLM API
call_llm(Prompt) ->
    ApiKey = application:get_env(yawl, llm_api_key),
    ApiUrl = application:get_env(yawl, llm_api_url, <<"https://api.openai.com/v1">>),

    Request = #{
        model => <<"gpt-4">>,
        messages => [
            #{role => system, content => get_system_prompt()},
            #{role => user, content => Prompt}
        ],
        temperature => 0.3,
        max_tokens => 2000
    },

    Headers = [
        {<<"Authorization">>, <<"Bearer ", ApiKey/binary>>},
        {<<"Content-Type">>, <<"application/json">>}
    ],

    case httpc:request(post, {ApiUrl, Headers, <<"application/json">>, jsx:encode(Request)},
                      [], []) of
        {ok, {{_, 200, _}, _, Body}} ->
            Response = jsx:decode(Body, [return_maps]),
            Content = maps:get(<<"content">>, hd(maps:get(<<"choices">>, Response))),
            {ok, maps:get(<<"message">>, Content)};
        {ok, {{_, StatusCode, _}, _, Body}} ->
            {error, {http_error, StatusCode, Body}};
        {error, Reason} ->
            {error, Reason}
    end.

%% Build prompts
build_correctness_prompt(Info) ->
    io_lib:format(
        "Analyze this workflow for correctness issues:~n~n~p~n~n"
        "Check for:~n"
        "- Unreachable states~n"
        "- Dead transitions~n"
        "- Invalid transitions~n"
        "- Resource leaks~n~n"
        "Provide a JSON response with:~n"
        "{result: valid/invalid, confidence: 0-1, explanation: string, issues: []}",
        [Info]
    ).

build_soundness_prompt(Info) ->
    io_lib:format(
        "Analyze this workflow for soundness:~n~n~p~n~n"
        "Check for:~n"
        "- Deadlocks~n"
        "- Livelocks~n"
        "- Unbounded states~n"
        "- Proper termination~n~n"
        "Provide a JSON response with:~n"
        "{result: sound/unsound, confidence: 0-1, explanation: string, deadlocks: []}",
        [Info]
    ).

build_completeness_prompt(Info, Options) ->
    CheckPaths = maps:get(check_paths, Options, true),
    io_lib:format(
        "Analyze this workflow for completeness:~n~n~p~n~n"
        "Check for:~n"
        "- Missing error handling~n"
        "- Incomplete paths~n"
        "- Unhandled edge cases~n"
        "- Missing validation~n~n"
        "Check all paths: ~p~n~n"
        "Provide a JSON response with:~n"
        "{result: complete/incomplete, confidence: 0-1, explanation: string, missing: []}",
        [Info, CheckPaths]
    ).

%% Parse responses
parse_correctness_response(Response) ->
    %% Extract JSON from response
    case extract_json(Response) of
        {ok, Json} ->
            #aspect_result{
                aspect = correctness,
                result = maps:get(<<"result">>, Json),
                confidence = maps:get(<<"confidence">>, Json),
                explanation = maps:get(<<"explanation">>, Json),
                issues = maps:get(<<"issues">>, Json, [])
            };
        {error, Reason} ->
            {error, Reason}
    end.

%% Extract JSON from LLM response
extract_json(Text) ->
    %% Find JSON code blocks
    case re:run(Text, "```json\\s*(.+?)\\s*```", [{capture, all, list}]) of
        {match, [_, Json]} ->
            {ok, jsx:decode(list_to_binary(Json), [return_maps])};
        nomatch ->
            %% Try to find plain JSON
            case re:run(Text, "\\{.+\\}", [{capture, all, list}]) of
                {match, [Json]} ->
                    {ok, jsx:decode(list_to_binary(Json), [return_maps])};
                nomatch ->
                    {error, no_json_found}
            end
    end.

%% Get system prompt
get_system_prompt() ->
    <<"You are an expert in workflow verification and Petri net analysis. "
      "Analyze workflows for correctness, soundness, completeness, and consistency. "
      "Always respond with valid JSON in the specified format.">>.

%% Aggregate results
aggregate_results(Results) ->
    case lists:all(fun(R) ->
        case R of
            {ok, #aspect_result{result := <<"valid">>}} -> true;
            {ok, #aspect_result{result := <<"sound">>}} -> true;
            {ok, #aspect_result{result := <<"complete">>}} -> true;
            {ok, #aspect_result{result := <<"consistent">>}} -> true;
            _ -> false
        end
    end, Results) of
        true -> valid;
        false -> invalid
    end.
```

## Data Structures

```erlang
-record(validation_result, {
    workflow_id :: binary(),
    validation_id :: binary(),
    timestamp :: integer(),
    overall_result :: valid | invalid | warning,
    aspects :: map(),  %% #{aspect => aspect_result}
    suggestions :: [binary()],
    model_info :: map()
}).

-record(aspect_result, {
    aspect :: atom(),
    result :: binary(),
    confidence :: float(),
    explanation :: binary(),
    issues :: [term()],
    suggestions :: [binary()]
}).

-record(comparison_result, {
    workflow_id_1 :: binary(),
    workflow_id_2 :: binary(),
    equivalent :: boolean(),
    similarity_score :: float(),
    differences :: map()
}).
```

## REST API

### Validate Workflow

```bash
curl -X POST http://localhost:8081/api/research/llm/validate \
  -H "Content-Type: application/json" \
  -d '{
    "workflow_id": "seq_abc123",
    "aspects": ["correctness", "soundness", "completeness", "consistency"],
    "options": {
      "explain_errors": true,
      "suggest_fixes": true
    }
  }'
```

### Compare Workflows

```bash
curl -X POST http://localhost:8081/api/research/llm/compare \
  -H "Content-Type: application/json" \
  -d '{
    "workflow_id_1": "seq_abc123",
    "workflow_id_2": "seq_def456",
    "comparison_type": "equivalence"
  }'
```

## Use Cases

### Automated Workflow Review

Automatically review workflows before deployment:

```erlang
{ok, Result} = yawl_llm_validator:validate(WorkflowId, [
    correctness, soundness, completeness
]),
case Result#validation_result.overall_result of
    valid -> deploy_workflow(WorkflowId);
    invalid -> handle_validation_errors(Result)
end.
```

### Workflow Comparison

Compare refactored workflows for equivalence:

```erlang
{ok, Comparison} = yawl_llm_validator:compare(
    OriginalWorkflowId,
    RefactoredWorkflowId,
    equivalence
),
case Comparison#comparison_result.equivalent of
    true -> approve_refactor();
    false -> review_differences(Comparison)
end.
```

---

Next: [OCPM](ocpm.md) | [Back to Overview](overview.md)
