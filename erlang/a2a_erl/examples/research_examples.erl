%%%-------------------------------------------------------------------
%%% @doc
%%% Research Modules Examples
%%%
%%% Practical examples demonstrating the use of research modules
%%% integrated from van der Aalst's 2025-2026 papers.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(research_examples).
-author("A2A Team").
-export([
    % Reachability examples
    reachability_example/0,
    admissibility_example/0,
    concurrency_analysis_example/0,

    % Partial order examples
    partial_order_discovery_example/0,
    partial_order_to_model_example/0,

    % LLM validation examples
    llm_validation_example/0,
    hallucination_detection_example/0,
    llm_generation_example/0,

    % OCPM examples
    ocpm_logging_example/0,
    ocpm_query_example/0,
    ocpm_ai_grounding_example/0,

    % CPN examples
    cpn_colored_tokens_example/0,
    cpn_guards_example/0,
    cpn_json_export_example/0
]).

-include("yawl_types.hrl").

%%====================================================================
%% Reachability Analysis Examples (Paper 2602.02447)
%%====================================================================

%% @doc Basic reachability checking example.
reachability_example() ->
    io:format("~n=== Reachability Analysis Example ===~n"),

    % Start the reachability server
    {ok, _} = yawl_reachability:start_link(),

    % Define a target marking
    TargetMarking = #{
        p_order_created => [token],
        p_payment_pending => [],
        p_order_completed => []
    },

    % Check if marking is reachable
    Result = yawl_reachability:is_reachable(ordering_workflow, TargetMarking),

    case Result of
        #{is_reachable := true} ->
            io:format("✓ Target marking is REACHABLE~n");
        #{is_reachable := false} ->
            io:format("✗ Target marking is NOT reachable~n")
    end,

    % Get detailed diagnostics
    Diagnostics = yawl_reachability:reachability_diagnostics(
        ordering_workflow,
        TargetMarking
    ),
    io:format("Diagnostics: ~p~n", [Diagnostics]),

    ok.

%% @doc Admissibility checking example.
admissibility_example() ->
    io:format("~n=== Admissibility Checking Example ===~n"),

    % A marking is admissible if all places are pairwise concurrent
    AdmissibleMarking = #{
        p_branch_a => [token],
        p_branch_b => [token],
        p_branch_c => [token]
    },

    IsAdmissible = yawl_reachability:is_admissible(AdmissibleMarking),
    io:format("Marking is admissible: ~p~n", [IsAdmissible]),

    % Find maximum admissible marking
    Places = [p_branch_a, p_branch_b, p_branch_c, p_branch_d],
    MaxAdmissible = yawl_reachability:maximum_admissible(Places),
    io:format("Maximum admissible marking: ~p~n", [MaxAdmissible]),

    ok.

%% @doc Concurrency analysis example.
concurrency_analysis_example() ->
    io:format("~n=== Concurrency Analysis Example ===~n"),

    % Check if two places are concurrent
    AreConcurrent = yawl_reachability:are_concurrent(
        ordering_workflow,
        p_payment_pending,
        p_shipment_ready
    ),
    io:format("Places are concurrent: ~p~n", [AreConcurrent]),

    % Get all concurrent place pairs
    Places = [p_start, p_validated, p_paid, p_shipped, p_completed],
    ConcurrentPairs = yawl_reachability:concurrent_places(
        ordering_workflow,
        Places
    ),
    io:format("Concurrent pairs: ~p~n", [ConcurrentPairs]),

    ok.

%%====================================================================
%% Partial Order Discovery Examples (Paper 2509.15346)
%%====================================================================

%% @doc Partial order discovery from event log.
partial_order_discovery_example() ->
    io:format("~n=== Partial Order Discovery Example ===~n"),

    % Create sample event log with concurrent activities
    EventLog = #{
        traces => [
            #{
                trace_id => <<"trace1">>,
                events => [
                    #{id => <<"e1">>, activity => <<"A">>, timestamp => 1000},
                    #{id => <<"e2">>, activity => <<"B">>, timestamp => 2000},
                    #{id => <<"e3">>, activity => <<"C">>, timestamp => 3000}
                ]
            },
            #{
                trace_id => <<"trace2">>,
                events => [
                    #{id => <<"e4">>, activity => <<"A">>, timestamp => 1000},
                    #{id => <<"e5">>, activity => <<"C">>, timestamp => 2000},
                    #{id => <<"e6">>, activity => <<"B">>, timestamp => 3000}
                ]
            }
        ]
    },

    % Convert to partial order
    {ok, PartialOrder} = yawl_partial_order:event_log_to_partial_order(EventLog),

    % Get concurrent events
    ConcurrentEvents = yawl_partial_order:concurrent_events(
        maps:get(traces, EventLog, [])
    ),
    io:format("Concurrent events: ~p~n", [ConcurrentEvents]),

    % Export partial order XES
    XESBinary = yawl_partial_order:export_partial_order_xes(PartialOrder),
    io:format("Partial order XES exported: ~p bytes~n", [byte_size(XESBinary)]),

    ok.

%% @doc Partial order to workflow model conversion.
partial_order_to_model_example() ->
    io:format("~n=== Partial Order to Model Example ===~n"),

    % Create partial order from event log
    EventLog = #{
        events => [
            #{id => <<"e1">>, activity => <<"start">>},
            #{id => <<"e2">>, activity => <<"process_a">>},
            #{id => <<"e3">>, activity => <<"process_b">>},
            #{id => <<"e4">>, activity => <<"end">>}
        ],
        order => #{
            <<"e1">> => [<<"e2">>, <<"e3">>],
            <<"e2">> => [<<"e4">>],
            <<"e3">> => [<<"e4">>]
        },
        concurrent => sets:from_list([{<<"e2">>, <<"e3">>}])
    },

    % Convert to workflow model
    Model = yawl_partial_order:partial_order_to_model(EventLog),

    io:format("Model type: ~p~n", [maps:get(type, Model)]),
    io:format("Activities: ~p~n", [maps:get(activities, Model)]),
    io:format("Sound by construction: ~p~n", [maps:get(is_sound, Model)]),

    ok.

%%====================================================================
%% LLM Validation Examples (Paper 2509.15336)
%%====================================================================

%% @doc LLM model validation against XES log.
llm_validation_example() ->
    io:format("~n=== LLM Validation Example ===~n"),

    % Start LLM validator server
    {ok, _} = yawl_llm_validator:start_link(),

    % Create a standard process model
    StandardModel = yawl_llm_validator:create_standard_process(),

    % Load XES log
    {ok, XESLog} = file:read_file("priv/xes_samples/standard_process.xes"),

    % Validate model against XES
    ValidationResult = yawl_llm_validator:validate_against_xes(
        StandardModel,
        XESLog
    ),

    % Print validation result
    IsValid = maps:get(is_valid, ValidationResult),
    Fidelity = maps:get(fidelity, ValidationResult),

    io:format("Model valid: ~p~n", [IsValid]),
    io:format("Fidelity score: ~.2f~n", [Fidelity]),

    case IsValid of
        true -> io:format("✓ Model is valid~n");
        false ->
            io:format("✗ Model has issues~n"),
            Report = yawl_llm_validator:hallucination_report(ValidationResult),
            io:format("Report: ~p~n", [Report])
    end,

    ok.

%% @doc Hallucination detection example.
hallucination_detection_example() ->
    io:format("~n=== Hallucination Detection Example ===~n"),

    % Create atypical process (designed to trigger hallucinations)
    AtypicalModel = yawl_llm_validator:create_atypical_process(),

    % Load standard XES log (mismatch should trigger detection)
    {ok, StandardXES} = file:read_file("priv/xes_samples/standard_process.xes"),

    % Detect contradictions
    Contradictions = yawl_llm_validator:detect_contradictions(
        AtypicalModel,
        StandardXES
    ),

    io:format("Contradictions found: ~p~n", [length(Contradictions)]),

    lists:foreach(fun(Contradiction) ->
        Type = maps:get(type, Contradiction),
        Desc = maps:get(description, Contradiction),
        io:format("  - ~s: ~s~n", [Type, Desc])
    end, Contradictions),

    % Get fidelity score
    Fidelity = yawl_llm_validator:fidelity_score(AtypicalModel, StandardXES),
    io:format("Fidelity score: ~.2f (low = likely hallucination)~n", [Fidelity]),

    ok.

%% @doc LLM workflow generation example.
llm_generation_example() ->
    io:format("~n=== LLM Generation Example ===~n"),

    % Generate workflow from description
    Description = <<
        "Order fulfillment workflow: "
        "1. Validate order details"
        "2. Process payment"
        "3. Prepare shipment"
        "4. Complete order"
    >>,

    case yawl_llm_validator:llm_generate_model(Description) of
        {ok, GeneratedModel} ->
            io:format("✓ Model generated successfully~n"),
            io:format("Activities: ~p~n", [
                maps:get(activities, GeneratedModel, [])
            ]);
        {error, Reason} ->
            io:format("✗ Generation failed: ~p~n", [Reason])
    end,

    ok.

%%====================================================================
%% OCPM Examples (Paper 2508.00116)
%%====================================================================

%% @doc Object-centric event logging example.
ocpm_logging_example() ->
    io:format("~n=== OCPM Logging Example ===~n"),

    % Start OCPM server
    {ok, _} = yawl_ocpm:start_link(),

    % Log multi-object event
    Event = #{
        event_id => <<"evt001">>,
        timestamp => erlang:monotonic_time(millisecond),
        activity => <<"order_created">>,
        objects => #{
            <<"order">> => [<<"order123">>],
            <<"customer">> => [<<"cust456">>],
            <<"item">> => [<<"item789">>, <<"item790">>]
        }
    },

    yawl_ocpm:log_multi_object_event(
        [<<"order">>, <<"customer">>, <<"item">>],
        Event
    ),
    io:format("✓ Multi-object event logged~n"),

    % Log payment event
    PaymentEvent = #{
        event_id => <<"evt002">>,
        timestamp => erlang:monotonic_time(millisecond) + 100,
        activity => <<"payment_processed">>,
        objects => #{
            <<"order">> => [<<"order123">>],
            <<"payment">> => [<<"pay101">>]
        }
    },

    yawl_ocpm:log_multi_object_event([<<"order">>, <<"payment">>], PaymentEvent),
    io:format("✓ Payment event logged~n"),

    ok.

%% @doc OCPM query example.
ocpm_query_example() ->
    io:format("~n=== OCPM Query Example ===~n"),

    % Query object lifecycle
    Lifecycle = yawl_ocpm:pi_object_lifecycle(<<"order123">>),
    io:format("Order lifecycle: ~p~n", [Lifecycle]),

    % Query inter-object dependencies
    Deps = yawl_ocpm:pi_inter_object_dependencies(),
    io:format("Object dependencies: ~p~n", [Deps]),

    % Extract events for specific object type
    CurrentLog = yawl_ocpm:get_current_log(),
    OrderEvents = yawl_ocpm:extract_object_type(<<"order">>, CurrentLog),
    io:format("Order events: ~p~n", [length(OrderEvents)]),

    ok.

%% @doc OCPM AI grounding example.
ocpm_ai_grounding_example() ->
    io:format("~n=== OCPM AI Grounding Example ===~n"),

    % Get current OCPM log
    OCLog = yawl_ocpm:get_current_log(),

    % Ground generative AI
    GroundedModel = yawl_ocpm:ground_generative_ai(OCLog),
    io:format("Grounded model: ~p~n", [GroundedModel]),

    % Ground predictive AI
    Predictions = yawl_ocpm:ground_predictive_ai(OCLog),
    io:format("Predictions: ~p~n", [Predictions]),

    % Ground prescriptive AI
    Recommendations = yawl_ocpm:ground_prescriptive_ai(OCLog),
    io:format("Recommendations: ~p~n", [Recommendations]),

    ok.

%%====================================================================
%% CPN Examples (Paper 2506.12238)
%%====================================================================

%% @doc Colored tokens example.
cpn_colored_tokens_example() ->
    io:format("~n=== CPN Colored Tokens Example ===~n"),

    % Start CPN server
    {ok, _} = yawl_cpn:start_link(),

    % Create color sets
    OrderColorSet = yawl_cpn:create_color_set(order, record),
    ItemColorSet = yawl_cpn:create_color_set(item, product),

    io:format("✓ Color sets created~n"),

    % Create timed tokens
    OrderToken = yawl_cpn:create_timed_token(
        #{
            order_id => 123,
            customer_id => <<"cust456">>,
            total => 99.99
        },
        erlang:monotonic_time(millisecond)
    ),

    io:format("Order token: ~p~n", [OrderToken]),

    % Create marking with colored tokens
    Marking = #{
        p_orders => [OrderToken],
        p_payments => [],
        p_completed => []
    },

    io:format("Marking: ~p~n", [Marking]),

    ok.

%% @doc CPN guards example.
cpn_guards_example() ->
    io:format("~n=== CPN Guards Example ===~n"),

    % Create marking with test data
    Marking = #{
        p_input => [
            yawl_cpn:create_timed_token(#{amount => 100}, 0),
            yawl_cpn:create_timed_token(#{amount => 0}, 0),
            yawl_cpn:create_timed_token(#{amount => -50}, 0)
        ]
    },

    % Define guard expression
    Guard = {amount, '>', 0},

    % Evaluate guard against marking
    Result = yawl_cpn:evaluate_guard(Guard, Marking),
    io:format("Guard evaluation result: ~p~n", [Result]),

    % Test fire transition with guard
    case yawl_cpn:fire_transition_with_color(
        t_process,
        #{guard => Guard},
        Marking
    ) of
        {ok, NewMarking} ->
            io:format("✓ Transition fired, new marking: ~p~n", [NewMarking]);
        {error, Reason} ->
            io:format("✗ Transition failed: ~p~n", [Reason])
    end,

    ok.

%% @doc CPN JSON export example.
cpn_json_export_example() ->
    io:format("~n=== CPN JSON Export Example ===~n"),

    % Export workflow to CPN JSON
    CPNJSON = yawl_cpn:workflow_to_cpn_json(ordering_workflow),
    io:format("CPN JSON exported: ~p bytes~n", [byte_size(CPNJSON)]),

    % Save to file
    file:write_file("priv/benchmarks/ordering_workflow_cpn.json", CPNJSON),
    io:format("✓ Saved to priv/benchmarks/ordering_workflow_cpn.json~n"),

    % Format for LLM
    LLMJSON = yawl_cpn:llm_format_workflow(ordering_workflow),
    io:format("LLM JSON: ~p bytes~n", [byte_size(LLMJSON)]),

    % Parse LLM response (simulated)
    LLMResponse = <<"
    {
        \"places\": [
            {\"id\": \"p1\", \"name\": \"Start\"},
            {\"id\": \"p2\", \"name\": \"End\"}
        ],
        \"transitions\": [
            {\"id\": \"t1\", \"name\": \"Process\", \"guard\": \"true\"}
        ]
    }
    ">>,

    case yawl_cpn:parse_llm_workflow(LLMResponse) of
        {ok, ParsedModel} ->
            io:format("✓ LLM workflow parsed successfully~n"),
            io:format("Parsed: ~p~n", [ParsedModel]);
        {error, Reason} ->
            io:format("✗ Parse failed: ~p~n", [Reason])
    end,

    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
%% Print example header.
print_header(Title) ->
    io:format("~n~s~n", [lists:duplicate(60, "=")]),
    io:format("~s~n", [Title]),
    io:format("~s~n", [lists:duplicate(60, "=")]).

%% @private
%% Print success message.
print_success(Message) ->
    io:format("✓ ~s~n", [Message]).

%% @private
%% Print error message.
print_error(Message) ->
    io:format("✗ ~s~n", [Message]).
