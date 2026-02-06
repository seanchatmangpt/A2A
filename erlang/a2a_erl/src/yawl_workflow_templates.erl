%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Workflow Template System
%%%
%%% This module provides a template system for reusable workflow patterns.
%%% It supports:
%%%
%%% - Pre-built workflow templates for common scenarios
%%% - Template parameterization and customization
%%% - Template validation and instantiation
%%% - Template storage and retrieval
%%% - Template composition for complex workflows
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_workflow_templates).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([
    start_link/0,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% API exports - Template management
-export([
    register_template/2,
    get_template/1,
    list_templates/0,
    delete_template/1,
    instantiate_template/2
]).

%% API exports - Predefined templates
-export([
    get_approval_template/0,
    get_parallel_processing_template/0,
    get_data_pipeline_template/0,
    get_batch_processing_template/0,
    get_retry_workflow_template/0,
    get_milestone_template/0,
    get_cancellation_template/0
]).

%% API exports - Template composition
-export([
    compose_templates/2,
    create_template_from_workflow/2
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    templates :: map(),
    predefined :: map()
}).

-record(template, {
    id :: binary(),
    name :: binary(),
    description :: binary(),
    category :: binary(),
    pattern_type :: atom(),
    base_config :: map(),
    parameters :: [map()],  %% [{name, type, default, description}]
    workflow_structure :: map(),
    metadata :: map()
}).

-type template() :: #template{}.
-type template_id() :: binary().

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the template system.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Register a custom template.
-spec register_template(binary(), map()) -> {ok, template_id()} | {error, term()}.
register_template(Id, TemplateMap) ->
    gen_server:call(?MODULE, {register_template, Id, TemplateMap}).

%% @doc Get a template by ID.
-spec get_template(template_id()) -> {ok, map()} | {error, not_found}.
get_template(Id) ->
    gen_server:call(?MODULE, {get_template, Id}).

%% @doc List all available templates.
-spec list_templates() -> {ok, [map()]}.
list_templates() ->
    gen_server:call(?MODULE, list_templates).

%% @doc Delete a template.
-spec delete_template(template_id()) -> ok | {error, term()}.
delete_template(Id) ->
    gen_server:call(?MODULE, {delete_template, Id}).

%% @doc Instantiate a template with parameters.
-spec instantiate_template(template_id(), map()) -> {ok, map()} | {error, term()}.
instantiate_template(TemplateId, Parameters) ->
    gen_server:call(?MODULE, {instantiate_template, TemplateId, Parameters}).

%% @doc Get the approval workflow template.
-spec get_approval_template() -> map().
get_approval_template() ->
    #{
        id => <<"approval_workflow">>,
        name => <<"Approval Workflow">>,
        description => <<"Template for approval-based workflows with multiple stages">>,
        category => <<"business">>,
        pattern_type => exclusive_choice,
        base_config => #{
            conditions => [
                #{name => <<"approved">>, expression => <<"approval.status == approved">>},
                #{name => <<"rejected">>, expression => <<"approval.status == rejected">>},
                #{name => <<"escalate">>, expression => <<"approval.status == escalate">>}
            ],
            default_branch => rejected,
            timeout => 86400000  %% 24 hours
        },
        parameters => [
            #{name => <<"approvers">>, type => array, default => [], description => <<"List of approvers">>},
            #{name => <<"escalation_threshold">>, type => integer, default => 3, description => <<"Escalation after N rejections">>},
            #{name => <<"timeout">>, type => integer, default => 86400000, description => <<"Approval timeout in ms">>}
        ],
        workflow_structure => #{
            stages => [request, review, approve, complete],
            tasks => [
                #{id => submit_request, name => <<"Submit Request">>, type => human},
                #{id => manager_review, name => <<"Manager Review">>, type => human},
                #{id => auto_approve, name => <<"Auto Approve">>, type => automated},
                #{id => notify_result, name => <<"Notify Result">>, type => automated}
            ]
        }
    }.

%% @doc Get the parallel processing template.
-spec get_parallel_processing_template() -> map().
get_parallel_processing_template() ->
    #{
        id => <<"parallel_processing">>,
        name => <<"Parallel Processing">>,
        description => <<"Execute multiple tasks in parallel and aggregate results">>,
        category => <<"processing">>,
        pattern_type => parallel_split,
        base_config => #{
            branches => 3,
            aggregation => wait_all
        },
        parameters => [
            #{name => <<"num_branches">>, type => integer, default => 3, description => <<"Number of parallel branches">>},
            #{name => <<"tasks">>, type => array, default => [], description => <<"List of tasks to execute">>},
            #{name => <<"aggregation">>, type => string, default => <<"wait_all">>, description => <<"Aggregation strategy: wait_all, wait_first, majority">>}
        ],
        workflow_structure => #{
            stages => [split, process_parallel, aggregate, complete],
            tasks => [
                #{id => split_task, name => <<"Split">>, type => automated},
                #{id => process_1, name => <<"Process Branch 1">>, type => automated},
                #{id => process_2, name => <<"Process Branch 2">>, type => automated},
                #{id => process_3, name => <<"Process Branch 3">>, type => automated},
                #{id => aggregate, name => <<"Aggregate Results">>, type => automated}
            ]
        }
    }.

%% @doc Get the data pipeline template.
-spec get_data_pipeline_template() -> map().
get_data_pipeline_template() ->
    #{
        id => <<"data_pipeline">>,
        name => <<"Data Pipeline">>,
        description => <<"Sequential data processing pipeline with stages">>,
        category => <<"processing">>,
        pattern_type => basic_sequential,
        base_config => #{
            stages => [extract, transform, load]
        },
        parameters => [
            #{name => <<"stages">>, type => array, default => [], description => <<"Pipeline stages">>},
            #{name => <<"error_handling">>, type => string, default => <<"continue">>, description => <<"Error handling strategy">>},
            #{name => <<"batch_size">>, type => integer, default => 100, description => <<"Processing batch size">>}
        ],
        workflow_structure => #{
            stages => [extract, transform, validate, load],
            tasks => [
                #{id => extract_data, name => <<"Extract Data">>, type => automated},
                #{id => transform_data, name => <<"Transform Data">>, type => automated},
                #{id => validate_data, name => <<"Validate Data">>, type => automated},
                #{id => load_data, name => <<"Load Data">>, type => automated}
            ]
        }
    }.

%% @doc Get the batch processing template.
-spec get_batch_processing_template() -> map().
get_batch_processing_template() ->
    #{
        id => <<"batch_processing">>,
        name => <<"Batch Processing">>,
        description => <<"Process multiple items in batches with retry">>,
        category => <<"processing">>,
        pattern_type => multi_instance,
        base_config => #{
            num_instances => 10,
            allocation_strategy => round_robin
        },
        parameters => [
            #{name => <<"batch_size">>, type => integer, default => 10, description => <<"Size of each batch">>},
            #{name => <<"items">>, type => array, default => [], description => <<"Items to process">>},
            #{name => <<"max_retries">>, type => integer, default => 3, description => <<"Max retries per item">>},
            #{name => <<"continue_on_error">>, type => boolean, default => true, description => <<"Continue processing on error">>}
        ],
        workflow_structure => #{
            stages => [create_instances, process, collect, finalize],
            tasks => [
                #{id => create_batches, name => <<"Create Batches">>, type => automated},
                #{id => process_batch, name => <<"Process Batch">>, type => automated},
                #{id => collect_results, name => <<"Collect Results">>, type => automated},
                #{id => handle_errors, name => <<"Handle Errors">>, type => automated}
            ]
        }
    }.

%% @doc Get the retry workflow template.
-spec get_retry_workflow_template() -> map().
get_retry_workflow_template() ->
    #{
        id => <<"retry_workflow">>,
        name => <<"Retry Workflow">>,
        description => <<"Workflow with automatic retry and exponential backoff">>,
        category => <<"reliability">>,
        pattern_type => iterative_loop,
        base_config => #{
            condition => <<"result.status != success && retry_count < max_retries">>,
            max_iterations => 5
        },
        parameters => [
            #{name => <<"max_retries">>, type => integer, default => 3, description => <<"Maximum retry attempts">>},
            #{name => <<"backoff_base">>, type => integer, default => 1000, description => <<"Base backoff in ms">>},
            #{name => <<"backoff_multiplier">>, type => number, default => 2.0, description => <<"Backoff multiplier">>},
            #{name => <<"task">>, type => object, default => #{}, description => <<"Task to retry">>}
        ],
        workflow_structure => #{
            stages => [execute, check_result, backoff, retry_or_complete],
            tasks => [
                #{id => execute_task, name => <<"Execute Task">>, type => automated},
                #{id => check_status, name => <<"Check Status">>, type => automated},
                #{id => apply_backoff, name => <<"Apply Backoff">>, type => automated}
            ]
        }
    }.

%% @doc Get the milestone template.
-spec get_milestone_template() -> map().
get_milestone_template() ->
    #{
        id => <<"milestone_workflow">>,
        name => <<"Milestone Workflow">>,
        description => <<"Track workflow progress through milestones">>,
        category => <<"tracking">>,
        pattern_type => milestone,
        base_config => #{
            milestones => [
                #{id => m1, name => <<"Milestone 1">>, required => true},
                #{id => m2, name => <<"Milestone 2">>, required => true},
                #{id => m3, name => <<"Milestone 3">>, required => false}
            ]
        },
        parameters => [
            #{name => <<"milestones">>, type => array, default => [], description => <<"List of milestones">>},
            #{name => <<"notification_on_complete">>, type => boolean, default => true, description => <<"Notify on milestone complete">>}
        ],
        workflow_structure => #{
            stages => [start, milestone_1, milestone_2, milestone_3, complete],
            tasks => [
                #{id => start_workflow, name => <<"Start">>, type => automated},
                #{id => reach_m1, name => <<"Reach Milestone 1">>, type => automated},
                #{id => reach_m2, name => <<"Reach Milestone 2">>, type => automated},
                #{id => reach_m3, name => <<"Reach Milestone 3">>, type => automated},
                #{id => complete, name => <<"Complete">>, type => automated}
            ]
        }
    }.

%% @doc Get the cancellation template.
-spec get_cancellation_template() -> map().
get_cancellation_template() ->
    #{
        id => <<"cancellation_workflow">>,
        name => <<"Cancellation Workflow">>,
        description => <<"Workflow with cancellation support and cleanup">>,
        category => <<"control">>,
        pattern_type => cancelation,
        base_config => #{
            cancellation_scope => all,
            cleanup_on_cancel => true
        },
        parameters => [
            #{name => <<"cancellation_scope">>, type => string, default => <<"all">>, description => <<"Cancellation scope: all, current_branch, subprocess">>},
            #{name => <<"cleanup_actions">>, type => array, default => [], description => <<"Actions to run on cancellation">>},
            #{name => <<"allow_partial_completion">>, type => boolean, default => true, description => <<"Allow partial completion on cancel">>}
        ],
        workflow_structure => #{
            stages => [start, task1, task2, task3, cleanup, complete],
            tasks => [
                #{id => start_workflow, name => <<"Start">>, type => automated},
                #{id => task_a, name => <<"Task A">>, type => automated, cancellable => true},
                #{id => task_b, name => <<"Task B">>, type => automated, cancellable => true},
                #{id => task_c, name => <<"Task C">>, type => automated, cancellable => true},
                #{id => cleanup_resources, name => <<"Cleanup">>, type => automated, run_on_cancel => true}
            ]
        }
    }.

%% @doc Compose multiple templates into a single workflow.
-spec compose_templates([binary()], map()) -> {ok, map()} | {error, term()}.
compose_templates(TemplateIds, Options) ->
    gen_server:call(?MODULE, {compose_templates, TemplateIds, Options}).

%% @doc Create a template from an existing workflow.
-spec create_template_from_workflow(binary(), map()) -> {ok, template_id()} | {error, term()}.
create_template_from_workflow(WorkflowId, Options) ->
    gen_server:call(?MODULE, {create_template_from_workflow, WorkflowId, Options}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    Predefined = initialize_predefined_templates(),
    State = #state{
        templates = #{},
        predefined = Predefined
    },
    {ok, State}.

%% @private
handle_call({register_template, Id, TemplateMap}, _From, State) ->
    {Reply, NewState} = do_register_template(Id, TemplateMap, State),
    {reply, Reply, NewState};

handle_call({get_template, Id}, _From, State) ->
    Reply = do_get_template(Id, State),
    {reply, Reply, State};

handle_call(list_templates, _From, State) ->
    Reply = do_list_templates(State),
    {reply, Reply, State};

handle_call({delete_template, Id}, _From, State) ->
    {Reply, NewState} = do_delete_template(Id, State),
    {reply, Reply, NewState};

handle_call({instantiate_template, TemplateId, Parameters}, _From, State) ->
    Reply = do_instantiate_template(TemplateId, Parameters, State),
    {reply, Reply, State};

handle_call({compose_templates, TemplateIds, Options}, _From, State) ->
    Reply = do_compose_templates(TemplateIds, Options, State),
    {reply, Reply, State};

handle_call({create_template_from_workflow, WorkflowId, Options}, _From, State) ->
    Reply = do_create_template_from_workflow(WorkflowId, Options, State),
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
initialize_predefined_templates() ->
    Templates = [
        {<<"approval_workflow">>, get_approval_template()},
        {<<"parallel_processing">>, get_parallel_processing_template()},
        {<<"data_pipeline">>, get_data_pipeline_template()},
        {<<"batch_processing">>, get_batch_processing_template()},
        {<<"retry_workflow">>, get_retry_workflow_template()},
        {<<"milestone_workflow">>, get_milestone_template()},
        {<<"cancellation_workflow">>, get_cancellation_template()}
    ],
    maps:from_list(Templates).

%% @private
do_register_template(Id, TemplateMap, State) ->
    Template = map_to_template(Id, TemplateMap),
    NewTemplates = maps:put(Id, Template, State#state.templates),
    NewState = State#state{templates = NewTemplates},
    {{ok, Id}, NewState}.

%% @private
map_to_template(Id, Map) ->
    #template{
        id = Id,
        name = maps_get(<<"name">>, Map, <<"unnamed">>),
        description = maps_get(<<"description">>, Map, <<"">>),
        category = maps_get(<<"category">>, Map, <<"custom">>),
        pattern_type = binary_to_atom(maps_get(<<"pattern_type">>, Map, <<"basic_sequential">>), utf8),
        base_config = maps_get(<<"base_config">>, Map, #{}),
        parameters = maps_get(<<"parameters">>, Map, []),
        workflow_structure = maps_get(<<"workflow_structure">>, Map, #{}),
        metadata = maps_get(<<"metadata">>, Map, #{})
    }.

%% @private
do_get_template(Id, State) ->
    case maps:get(Id, State#state.templates, undefined) of
        undefined ->
            case maps:get(Id, State#state.predefined, undefined) of
                undefined -> {error, not_found};
                Template -> {ok, Template}
            end;
        Template -> {ok, Template}
    end.

%% @private
do_list_templates(State) ->
    Custom = maps:map(fun(_Id, Template) ->
        template_to_summary_map(Template)
    end, State#state.templates),

    Predefined = maps:map(fun(_Id, Template) ->
        template_to_summary_map(Template)
    end, State#state.predefined),

    AllTemplates = maps:merge(Custom, Predefined),
    {ok, maps:values(AllTemplates)}.

%% @private
do_delete_template(Id, State) ->
    case maps:is_key(Id, State#state.templates) of
        false -> {error, not_found};
        true ->
            NewTemplates = maps:remove(Id, State#state.templates),
            NewState = State#state{templates = NewTemplates},
            {ok, NewState}
    end.

%% @private
do_instantiate_template(TemplateId, Parameters, State) ->
    case do_get_template(TemplateId, State) of
        {error, not_found} -> {error, template_not_found};
        {ok, Template} when is_map(Template) ->
            instantiate_template_from_map(Template, Parameters)
    end.

%% @private
instantiate_template_from_map(Template, Parameters) ->
    BaseConfig = maps:get(<<"base_config">>, Template, #{}),
    TemplateParams = maps:get(<<"parameters">>, Template, []),

    %% Validate required parameters
    ValidationResults = lists:map(fun(Param) ->
        Name = maps:get(<<"name">>, Param),
        Required = maps:get(<<"required">>, Param, false),
        case Required andalso not maps:is_key(Name, Parameters) of
            true -> {error, {missing_parameter, Name}};
            false -> ok
        end
    end, TemplateParams),

    HasErrors = lists:any(fun(E) -> E =/= ok end, ValidationResults),

    case HasErrors of
        true ->
            Errors = [E || E <- ValidationResults, E =/= ok],
            {error, {parameter_errors, Errors}};
        false ->
            %% Merge parameters with defaults
            MergedConfig = lists:foldl(fun(Param, AccConfig) ->
                Name = maps:get(<<"name">>, Param, <<>>),
                Default = maps:get(<<"default">>, Param, undefined),
                Value = maps:get(Name, Parameters, Default),
                case Value of
                    undefined -> AccConfig;
                    _ -> maps:put(Name, Value, AccConfig)
                end
            end, BaseConfig, TemplateParams),

            %% Apply parameter overrides
            FinalConfig = maps:merge(BaseConfig, Parameters),

            #{
                pattern_type => maps:get(<<"pattern_type">>, Template, basic_sequential),
                config => FinalConfig,
                workflow_structure => maps:get(<<"workflow_structure">>, Template, #{}),
                template_id => maps_get(<<"id">>, Template, <<>>),
                parameters => Parameters
            }
    end.

%% @private
do_compose_templates(TemplateIds, Options, State) ->
    %% Load all templates
    LoadResults = lists:map(fun(Id) ->
        do_get_template(Id, State)
    end, TemplateIds),

    case lists:all(fun(R) -> element(1, R) =:= ok end, LoadResults) of
        false ->
            {error, template_not_found};
        true ->
            Templates = [T || {ok, T} <- LoadResults],
            compose_template_list(Templates, Options)
    end.

%% @private
compose_template_list(Templates, Options) ->
    %% Compose templates by linking them sequentially
    ComposedName = maps:get(<<"name">>, Options, <<"composed_workflow">>),

    %% Merge workflow structures
    AllStages = lists:flatmap(fun(T) ->
        Structure = maps:get(<<"workflow_structure">>, T, #{}),
        maps:get(<<"stages">>, Structure, [])
    end, Templates),

    %% Remove duplicates while preserving order
    UniqueStages = lists:usort(AllStages),

    #{
        id => generate_template_id(),
        name => ComposedName,
        description => <<"Composed workflow from ", (integer_to_binary(length(Templates)))/binary, " templates">>,
        pattern_type => basic_sequential,
        base_config => #{
            composed_from => [maps_get(<<"id">>, T, <<>>) || T <- Templates]
        },
        workflow_structure => #{
            stages => UniqueStages,
            templates => [maps_get(<<"id">>, T, <<>>) || T <- Templates]
        }
    }.

%% @private
do_create_template_from_workflow(WorkflowId, Options, State) ->
    %% Load the workflow definition
    case yawl_persistence:load_workflow(WorkflowId) of
        {error, not_found} -> {error, workflow_not_found};
        {ok, Workflow} ->
            TemplateName = maps_get(<<"name">>, Options,
                <<"Template from ", WorkflowId/binary>>),

            Template = #{
                id => generate_template_id(),
                name => TemplateName,
                description => maps_get(<<"description">>, Options,
                    <<"Template created from workflow ", WorkflowId/binary>>),
                category => maps_get(<<"category">>, Options, <<"custom">>),
                pattern_type => Workflow#yawl_workflow_persist.pattern_type,
                base_config => Workflow#yawl_workflow_persist.data,
                workflow_structure => #{
                    derived_from => WorkflowId
                },
                parameters => maps_get(<<"parameters">>, Options, [])
            },

            NewState = State#state{templates = maps:put(Template#{
                <<"id">> => Template
            }, State#state.templates)},

            {{ok, maps:get(<<"id">>, Template)}, NewState}
    end.

%% @private
template_to_summary_map(Template) when is_map(Template) ->
    #{
        id => maps_get(<<"id">>, Template, <<>>),
        name => maps_get(<<"name">>, Template, <<"unnamed">>),
        description => maps_get(<<"description">>, Template, <<"">>),
        category => maps_get(<<"category">>, Template, <<"custom">>),
        pattern_type => maps_get(<<"pattern_type">>, Template, basic_sequential)
    };
template_to_summary_map(#template{} = T) ->
    #{
        id => T#template.id,
        name => T#template.name,
        description => T#template.description,
        category => T#template.category,
        pattern_type => T#template.pattern_type
    }.

%% @private
generate_template_id() ->
    UniqueId = erlang:unique_integer([positive, monotonic]),
    Time = erlang:monotonic_time(millisecond),
    <<"tpl_", Time:64, "_", UniqueId:64>>.

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
