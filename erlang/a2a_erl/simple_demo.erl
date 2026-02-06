-module(simple_demo).
-export([run/0]).

run() ->
    io:format("=== A2A Erlang YAWL Workflow Demo ===~n~n"),

    %% Start event manager
    {ok, _} = yawl_a2a_events:start_link(),

    %% Subscribe to events
    {ok, _} = yawl_a2a_events:subscribe(self()),

    io:format("Running ordering workflow simulation...~n"),
    ordering_workflow:simulate_normal_approval(),

    %% Collect events
    timer:sleep(100),
    Events = yawl_a2a_events:get_event_history(),

    io:format("~nEvents captured: ~p~n", [length(Events)]),

    %% Show first few events
    case Events of
        [] -> io:format("No events captured~n");
        _ ->
            lists:foreach(fun(Event) ->
                io:format("  Event: ~p~n", [Event])
            end, lists:sublist(Events, 5))
    end,

    %% Show available workflows
    io:format("~nAvailable workflows:~n"),
    io:format("  - ordering_workflow: PO creation and approval~n"),
    io:format("  - carrier_appointment_workflow: Carrier selection~n"),
    io:format("  - freight_in_transit_workflow: Shipment tracking~n"),
    io:format("  - freight_delivered_workflow: Claims and returns~n"),
    io:format("  - payment_workflow: Payment processing~n"),
    io:format("  - order_fulfillment_orchestration: Full orchestration~n"),

    io:format("~n=== Comparison Notes ===~n"),
    io:format("A2A Erlang uses:~n"),
    io:format("  - Real-time event bus (yawl_a2a_events)~n"),
    io:format("  - In-memory event history~n"),
    io:format("  - SSE streaming for web clients (yawl_sse)~n"),
    io:format("  - Petri net markings for state~n"),
    io:format("  - No XES logging~n"),

    io:format("~nCRE uses:~n"),
    io:format("  - IEEE 1849-2016 XES standard logging~n"),
    io:format("  - Persistent XML trace files~n"),
    io:format("  - Pattern-level event recording~n"),
    io:format("  - gen_pnet Petri net implementation~n"),

    io:format("~nDemo complete!~n"),
    ok.
