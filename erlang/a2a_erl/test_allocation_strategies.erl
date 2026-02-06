#!/usr/bin/env escript

%% Test script for allocation strategies in YAWL resource manager
%% This script demonstrates the round_robin and random allocation strategies

main(_) ->
    %% Start the resource manager
    case whereis(yawl_resource_manager) of
        undefined ->
            case start_link() of
                {ok, Pid} ->
                    io:format("Resource manager started: ~p~n", [Pid]);
                {error, Reason} ->
                    io:format("Failed to start resource manager: ~p~n", [Reason]),
                    halt(1)
            end;
        Pid ->
            io:format("Resource manager already running: ~p~n", [Pid])
    end,

    %% Test round_robin allocation
    test_round_robin_allocation(),

    %% Test random allocation
    test_random_allocation(),

    %% Test least_loaded (default)
    test_least_loaded_allocation(),

    %% Clean up
    stop().

start_link() ->
    case start() of
        {ok, Pid} -> {ok, Pid};
        {error, _} = Error -> Error
    end.

start() ->
    code:add_patha("ebin"),
    case yawl_resource_manager:start_link() of
        {ok, Pid} -> {ok, Pid};
        {error, Reason} -> {error, Reason}
    end.

stop() ->
    case whereis(yawl_resource_manager) of
        undefined -> ok;
        Pid -> Pid ! stop
    end.

test_round_robin_allocation() ->
    io:format("~n=== Testing Round Robin Allocation Strategy ===~n", []),

    %% Set round robin strategy
    case yawl_resource_manager:set_allocation_strategy(round_robin) of
        ok -> io:format("✓ Round robin strategy set successfully~n");
        {error, Reason1} -> io:format("✗ Failed to set round robin strategy: ~p~n", [Reason1])
    end,

    %% Register test resources
    register_test_resources(),

    %% Allocate resources multiple times to demonstrate round robin behavior
    io:format("~nAllocating resources with round robin strategy:~n"),
    for(1, 5, fun(I) ->
        case yawl_resource_manager:allocate_resource(<<"workitem_", (integer_to_binary(I))/binary>>, []) of
            {ok, ResourceId, Resource} ->
                io:format("  Allocation ~p: ~p (~p)~n", [I, ResourceId, Resource]);
            {error, no_available_resources} ->
                io:format("  Allocation ~p: No available resources~n", [I]);
            {error, Reason2} ->
                io:format("  Allocation ~p: Error - ~p~n", [I, Reason2])
        end
    end).

test_random_allocation() ->
    io:format("~n=== Testing Random Allocation Strategy ===~n", []),

    %% Set random strategy
    case yawl_resource_manager:set_allocation_strategy(random) of
        ok -> io:format("✓ Random strategy set successfully~n");
        {error, Reason1} -> io:format("✗ Failed to set random strategy: ~p~n", [Reason1])
    end,

    %% Allocate resources to demonstrate random behavior
    io:format("~nAllocating resources with random strategy:~n"),
    for(1, 5, fun(I) ->
        case yawl_resource_manager:allocate_resource(<<"workitem_random_", (integer_to_binary(I))/binary>>, []) of
            {ok, ResourceId, Resource} ->
                io:format("  Random allocation ~p: ~p (~p)~n", [I, ResourceId, Resource]);
            {error, no_available_resources} ->
                io:format("  Random allocation ~p: No available resources~n", [I]);
            {error, Reason2} ->
                io:format("  Random allocation ~p: Error - ~p~n", [I, Reason2])
        end
    end).

test_least_loaded_allocation() ->
    io:format("~n=== Testing Least Loaded Allocation Strategy ===~n", []),

    %% Set least loaded strategy (default)
    case yawl_resource_manager:set_allocation_strategy(least_loaded) of
        ok -> io:format("✓ Least loaded strategy set successfully~n");
        {error, Reason1} -> io:format("✗ Failed to set least loaded strategy: ~p~n", [Reason1])
    end,

    %% Allocate resources to demonstrate least loaded behavior
    io:format("~nAllocating resources with least loaded strategy:~n"),
    for(1, 5, fun(I) ->
        case yawl_resource_manager:allocate_resource(<<"workitem_least_", (integer_to_binary(I))/binary>>, []) of
            {ok, ResourceId, Resource} ->
                io:format("  Least loaded allocation ~p: ~p (~p)~n", [I, ResourceId, Resource]);
            {error, no_available_resources} ->
                io:format("  Least loaded allocation ~p: No available resources~n", [I]);
            {error, Reason2} ->
                io:format("  Least loaded allocation ~p: Error - ~p~n", [I, Reason2])
        end
    end).

register_test_resources() ->
    io:format("~nRegistering test resources...~n"),

    %% Register human resources
    register_resource("human_1", human),
    register_resource("human_2", human),
    register_resource("human_3", human),

    %% Register service resources
    register_resource("service_1", service),
    register_resource("service_2", service),

    %% Register system resources
    register_resource("system_1", system),

    %% Make all resources available
    case yawl_resource_manager:list_resources() of
        {ok, Resources} ->
            lists:foreach(fun(Resource) ->
                ResourceId = maps:get(resource_id, Resource),
                make_resource_available(ResourceId)
            end, Resources);
        {error, Reason} ->
            io:format("  Failed to list resources: ~p~n", [Reason])
    end,

    io:format("✓ Test resources registered and available~n").

register_resource(Name, Type) ->
    case yawl_resource_manager:register_resource(Name, Type) of
        {ok, ResourceId} ->
            io:format("  Registered ~p (~p) as ~p~n", [Name, ResourceId, Type]);
        {error, Reason} ->
            io:format("  Failed to register ~p: ~p~n", [Name, Reason])
    end.

%% Update resource status to available after registration
make_resource_available(ResourceId) ->
    case yawl_resource_manager:update_resource_status(ResourceId, available) of
        ok -> io:format("  Made resource ~p available~n", [ResourceId]);
        {error, Reason} -> io:format("  Failed to make resource ~p available: ~p~n", [ResourceId, Reason])
    end.

for(Start, End, Fun) when Start =< End ->
    Fun(Start),
    for(Start + 1, End, Fun);
for(_, _, _) ->
    ok.