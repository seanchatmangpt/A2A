%%%-------------------------------------------------------------------
%%% @doc
%%% Research Module Examples
%%%
%%% This module contains working examples for all research modules.
%%% Copy and modify these examples for your use cases.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(research_examples).
-author("A2A Team").
-export([
    % Reachability examples
    reachability_basic/0,
    reachability_diagnostics/0,
    reachability_admissibility/0,

    % Partial order examples
    partial_order_basic/0,
    partial_order_to_model/0,
    partial_order_xes/0,

    % LLM validator examples
    llm_validate_basic/0,
    llm_fidelity_score/0,
    llm_test_scenarios/0,

    % OCPM examples
    ocpm_log_event/0,
    ocpm_order_fulfillment/0,
    ocpm_to_xes/0,

    % CPN examples
    cpn_colored_tokens/0,
    cpn_guard_evaluation/0,
    cpn_json_export/0,

    % Integration examples
    end_to_end_validation/0
]).

%%====================================================================
%% Reachability Analysis Examples
%%====================================================================

%% @doc Basic reachability check
reachability_basic() ->
    {ok, _Pid} = yawl_reachability:start_link(),

    % Define a simple workflow net
    % p1 -> t1 -> p2 -> t2 -> p3
    Workflow = ordering_workflow,

    % Check if marking is reachable
    Marking = #{p1 => [], p2 => [token], p3 => []},
    IsReachable = yawl_reachability:is_reachable(Workflow, Marking),

    io:format("Marking ~p is reachable: ~p~n", [Marking, IsReachable]),
    IsReachable.

%% @doc Full reachability diagnostics
reachability_diagnostics() ->
    {ok, _Pid} = yawl_reachability:start_link(),

    Workflow = ordering_workflow,
    Marking = #{p1 => [token], p2 => [token]},

    Diagnostics = yawl_reachability:get_reachability_diagnostics(Workflow, Marking),

    io:format("=== Reachability Diagnostics ===~n"),
    io:format("Reachable: ~p~n", [maps:get(reachable, Diagnostics)]),
    io:format("Admissible: ~p~n", [maps:get(admissible, Diagnostics)]),
    io:format("Diverging Transitions: ~p~n", [maps:get(diverging_transitions, Diagnostics, [])]),
    io:format("Concurrent Places: ~p~n", [maps:get(concurrent_places, Diagnostics, [])),

    Diagnostics.

%% @doc Admissibility and maximum admissible marking
reachability_admissibility() ->
    {ok, _Pid} = yawl_reachability:start_link(),

    Workflow = ordering_workflow,
    Places = [p1, p2, p3, p4],

    % Check if concurrent marking is admissible
    ConcurrentMarking = #{p1 => [token], p2 => [token]},
    IsAdmissible = yawl_reachability:is_admissible(Workflow, ConcurrentMarking),

    % Find maximum admissible marking
    MaxAdmissible = yawl_reachability:maximum_admissible(Workflow, Places),

    io:format("Is admissible: ~p~n", [IsAdmissible]),
    io:format("Maximum admissible: ~p~n", [MaxAdmissible]),

    {IsAdmissible, MaxAdmissible}.

%%====================================================================
%% Partial Order Examples
%%====================================================================

%% @doc Convert event log to partial order
partial_order_basic() ->
    {ok, _Pid} = yawl_partial_order:start_link(),

    % Create sample event log with concurrent activities
    EventLog = [
        #{id => <<"e1">>, timestamp => 1000, activity => <<"Start">>},
        #{id => <<"e2">>, timestamp => 2000, activity => <<"Check A">>},
        #{id => <<"e3">>, timestamp => 2000, activity => <<"Check B">>},  % Concurrent with e2
        #{id => <<"e4">>, timestamp => 3000, activity => <<"Complete">>}
    ],

    % Convert to partial order
    {ok, PO} = yawl_partial_order:event_log_to_partial_order(EventLog),

    % Check concurrency
    {ok, _} = yawl_partial_order:concurrent_events(
        maps:get(e2, EventLog),
        maps:get(e3, EventLog)
    ),

    io:format("Partial order: ~p~n", [PO]),
    PO.

%% @doc Convert partial order to workflow net
partial_order_to_model() ->
    {ok, _Pid} = yawl_partial_order:start_link(),

    EventLog = [
        #{id => <<"e1">>, timestamp => 1000, activity => <<"A">>},
        #{id => <<"e2">>, timestamp => 2000, activity => <<"B">>},
        #{id => <<"e3">>, timestamp => 3000, activity => <<"C">>}
    ],

    {ok, PO} = yawl_partial_order:event_log_to_partial_order(EventLog),
    {ok, WFNet} = yawl_partial_order:partial_order_to_workflow_net(PO),

    io:format("Generated workflow net: ~p~n", [WFNet]),
    WFNet.

%% @doc Export/import partial order XES
partial_order_xes() ->
    {ok, _Pid} = yawl_partial_order:start_link(),

    PO = #{
        events => [
            #{id => <<"e1">>, activity => <<"A">>},
            #{id => <<"e2">>, activity => <<"B">>}
        ],
        order => [{<<"e1">>, <<"e2">>}]
    },

    % Export to XES
    {ok, XES} = yawl_partial_order:export_partial_order_xes(PO),

    % Import back
    {ok, ImportedPO} = yawl_partial_order:import_partial_order_xes(XES),

    io:format("Exported XES size: ~p bytes~n", [byte_size(XES)]),
    io:format("Imported PO: ~p~n", [ImportedPO]),

    XES.

%%====================================================================
%% LLM Validator Examples
%%====================================================================

%% @doc Basic LLM model validation
llm_validate_basic() ->
    {ok, _Pid} = yawl_llm_validator:start_link(),

    % Sample LLM-generated model
    LLMModel = #{
        activities => [<<"Request">>, <<"Approve">>, <<"Reject">>, <<"Complete">>],
        transitions => [
            #{from => <<"Request">>, to => <<"Approve">>},
            #{from => <<"Request">>, to => <<"Reject">>},
            #{from => <<"Approve">>, to => <<"Complete">>}
        ]
    },

    % Sample XES log
    XESLog = #{
        traces => [
            #{events => [
                #{activity => <<"Request">>},
                #{activity => <<"Approve">>},
                #{activity => <<"Complete">>}
            ]}
        ]
    },

    % Validate
    Report = yawl_llm_validator:validate_against_xes(LLMModel, XESLog),

    io:format("=== Validation Report ===~n"),
    io:format("Valid: ~p~n", [maps:get(valid, Report, unknown)]),
    io:format("Fidelity: ~p~n", [maps:get(fidelity_score, Report, 0.0)]),

    Report.

%% @doc Calculate fidelity score
llm_fidelity_score() ->
    {ok, _Pid} = yawl_llm_validator:start_link(),

    LLMModel = #{activities => [<<"A">>, <<"B">>, <<"C">>]},
    XESLog = #{traces => [#{
        events => [
            #{activity => <<"A">>},
            #{activity => <<"B">>},
            #{activity => <<"C">>}
        ]
    }]},

    Fidelity = yawl_llm_validator:fidelity_score(LLMModel, XESLog),

    io:format("Fidelity score: ~.2f~n", [Fidelity]),
    Fidelity.

%% @doc Test with standard and atypical scenarios
llm_test_scenarios() ->
    {ok, _Pid} = yawl_llm_validator:start_link(),

    Standard = yawl_llm_validator:create_standard_process(),
    Atypical = yawl_llm_validator:create_atypical_process(),

    io:format("Standard process: ~p~n", [Standard]),
    io:format("Atypical process: ~p~n", [Atypical]),

    {Standard, Atypical}.

%%====================================================================
%% OCPM Examples
%%====================================================================

%% @doc Log a single object-centric event
ocpm_log_event() ->
    {ok, _Pid} = yawl_ocpm:start_link(),

    Event = #{
        id => <<"evt-001">>,
        timestamp => erlang:system_time(millisecond),
        objects => #{
            order => <<"order-123">>,
            item => <<"item-456">>,
            customer => <<"customer-789">>
        },
        activity => <<"Place Order">>
    },

    ok = yawl_ocpm:log_oc_event(Event),

    io:format("Logged event: ~p~n", [maps:get(id, Event))),
    ok.

%% @doc Complete order fulfillment OCPM example
ocpm_order_fulfillment() ->
    {ok, _Pid} = yawl_ocpm:start_link(),

    OrderId = <<"order-001">>,
    ItemId = <<"item-001">>,

    % Log order lifecycle
    Events = [
        #{
            id => <<"e1">>,
            timestamp => 1000,
            objects => #{order => OrderId, item => ItemId},
            activity => <<"Order Created">>
        },
        #{
            id => <<"e2">>,
            timestamp => 2000,
            objects => #{order => OrderId, payment => <<"pay-001">>},
            activity => <<"Payment Received">>
        },
        #{
            id => <<"e3">>,
            timestamp => 3000,
            objects => #{order => OrderId, shipment => <<"ship-001">>},
            activity => <<"Order Shipped">>
        },
        #{
            id => <<"e4">>,
            timestamp => 4000,
            objects => #{order => OrderId},
            activity => <<"Order Delivered">>
        }
    ],

    lists:foreach(fun(E) -> yawl_ocpm:log_oc_event(E) end, Events),

    io:format("Logged ~p events for order ~p~n", [length(Events), OrderId]),
    ok.

%% @doc Convert OCPM to standard XES
ocpm_to_xes() ->
    {ok, _Pid} = yawl_ocpm:start_link(),

    % Create OCEL log
    {ok, OCEL} = yawl_ocpm:create_ocel_log(),

    % Flatten to XES
    {ok, XES} = yawl_ocpm:ocpm_to_standard_xes(OCEL),

    % Extract by object type
    OrderEvents = yawl_ocpm:extract_object_type(<<"order">>, OCEL),

    io:format("Converted to XES with ~p traces~n", [length(maps:get(traces, XES, []))]),
    io:format("Order events: ~p~n", [OrderEvents]),

    XES.

%%====================================================================
%% CPN Examples
%%====================================================================

%% @doc Create and use colored tokens
cpn_colored_tokens() ->
    {ok, _Pid} = yawl_cpn:start_link(),

    % Define color set for order status
    {ok, StatusColorSet} = yawl_cpn:create_color_set(
        order_status,
        [pending, confirmed, shipped, delivered]
    ),

    % Create colored tokens
    Token1 = yawl_cpn:create_timed_token(#{status => confirmed}, 1000),
    Token2 = yawl_cpn:create_timed_token(#{status => shipped}, 2000),

    io:format("Color set: ~p~n", [StatusColorSet]),
    io:format("Colored tokens: ~p, ~p~n", [Token1, Token2]),

    {Token1, Token2}.

%% @doc Evaluate guard conditions
cpn_guard_evaluation() ->
    {ok, _Pid} = yawl_cpn:start_link(),

    Token = #{status => confirmed, amount => 100},
    Guard = #{status => confirmed, amount => {'>', 50}},

    {ok, Result} = yawl_cpn:evaluate_guard(Token, Guard),

    io:format("Guard evaluation result: ~p~n", [Result]),
    Result.

%% @doc Export workflow to CPN-JSON
cpn_json_export() ->
    {ok, _Pid} = yawl_cpn:start_link(),

    WorkflowId = ordering_workflow,

    % Export to CPN-JSON
    {ok, CPNJSON} = yawl_cpn:workflow_to_cpn_json(WorkflowId),

    % Export to LLM format
    {ok, LLMJSON} = yawl_cpn:llm_format_workflow(WorkflowId),

    io:format("CPN-JSON size: ~p bytes~n", [byte_size(CPNJSON)]),
    io:format("LLM-JSON size: ~p bytes~n", [byte_size(LLMJSON)]),

    {CPNJSON, LLMJSON}.

%%====================================================================
%% Integration Examples
%%====================================================================

%% @doc End-to-end validation: LLM -> Reachability -> OCPM
end_to_end_validation() ->
    % Start all modules
    {ok, _} = yawl_llm_validator:start_link(),
    {ok, _} = yawl_reachability:start_link(),
    {ok, _} = yawl_ocpm:start_link(),

    % Step 1: Generate model via LLM
    Description = <<"Order processing workflow with approval">>,
    {ok, LLMModel} = yawl_llm_validator:llm_generate_model(Description),

    % Step 2: Validate against XES evidence
    XESLog = #{traces => []},  % Load from file
    ValidationReport = yawl_llm_validator:validate_against_xes(LLMModel, XESLog),

    % Step 3: Check reachability
    case maps:get(valid, ValidationReport, true) of
        true ->
            % Step 4: Log to OCPM for grounding
            lists:foreach(fun(Act) ->
                yawl_ocpm:log_oc_event(#{
                    id => list_to_binary("evt-" ++ integer_to_list(erlang:unique_integer([positive]))),
                    timestamp => erlang:system_time(millisecond),
                    objects => #{workflow => <<"main">>},
                    activity => Act
                })
            end, maps:get(activities, LLMModel, [])),
            {ok, validated_and_logged};
        false ->
            {error, validation_failed}
    end.
