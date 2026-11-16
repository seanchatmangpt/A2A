# Resource Allocation in YAWL

## Overview

YAWL implements sophisticated capability-based resource allocation, enabling workflows to dynamically assign human resources, services, and system resources to workitems based on required capabilities and availability.

## Resource Types

### 1. Human Resources

People with specific skills and capabilities:

```erlang
-record(human_resource, {
    resource_id :: binary(),
    name :: binary(),
    capabilities :: [atom()],
    attributes :: map(),
    status :: resource_status(),
    current_load :: integer(),
    max_capacity :: integer(),
    schedule :: map()
}).

% Example human resource
JohnDoe = #human_resource{
    resource_id = <<"john_doe">>,
    name = <<"John Doe">>,
    capabilities = [approval, review, technical_review],
    attributes = #{
        department => <<"engineering">>,
        level => senior,
        location => <<"US-East">>
    },
    status = available,
    current_load = 0,
    max_capacity = 5,
    schedule = #{
        work_hours => #{1 => [9,17], 2 => [9,17], 3 => [9,17], 4 => [9,17], 5 => [9,17]},
        timezone => <<"America/New_York">>
    }
}.
```

### 2. Service Resources

External systems and APIs:

```erlang
-record(service_resource, {
    resource_id :: binary(),
    name :: binary(),
    capabilities :: [atom()],
    endpoint :: binary(),
    auth :: map(),
    status :: resource_status(),
    rate_limit :: map(),
    metadata :: map()
}).

% Example service resource
PaymentService = #service_resource{
    resource_id = <<"stripe_payment">>,
    name = <<"Stripe Payment Gateway">>,
    capabilities = [payment_processing, refund, subscription],
    endpoint => <<"https://api.stripe.com/v1">>,
    auth = #{type => bearer, token => <<"sk_live_...">>},
    status = available,
    rate_limit = #{max_requests => 100, window => 60000},
    metadata = #{provider => stripe, version => v1}
}.
```

### 3. System Resources

Internal services and processes:

```erlang
-record(system_resource, {
    resource_id :: binary(),
    name :: binary(),
    capabilities :: [atom()],
    node :: node(),
    status :: resource_status(),
    metrics :: map()
}).

% Example system resource
DataCluster = #system_resource{
    resource_id = <<"data_cluster_1">>,
    name => <<"Data Processing Cluster">>,
    capabilities = [data_processing, etl, analytics],
    node => 'data@node1.example.com',
    status = available,
    metrics = #{
        cpu_usage => 45.5,
        memory_usage => 67.2,
        disk_usage => 23.1
    }
}.
```

## Capability-Based Allocation

### Capability Registry

Resources are registered with their capabilities:

```erlang
%% Capability definitions
-define(APPROVAL, approval).
-define(REVIEW, review).
-define(TECHNICAL_REVIEW, technical_review).
-define(PAYMENT_PROCESSING, payment_processing).
-define(DATA_PROCESSING, data_processing).
-define(SHIPPING, shipping).
-define(NOTIFICATION, notification).

%% Register resource with capabilities
register_resource_with_capabilities(ResourceId, Capabilities) ->
    Resource = #yawl_resource_persist{
        resource_id = ResourceId,
        capabilities = Capabilities,
        status = available,
        current_load = 0,
        max_capacity = determine_capacity(Capabilities)
    },
    yawl_persistence:save_resource(Resource).
```

### Capability Matching

```erlang
%% Find resources with required capabilities
find_resources_by_capabilities(RequiredCapabilities) ->
    {ok, AllResources} = yawl_persistence:list_resources(),

    %% Filter by capability match
    lists:filter(fun(Resource) ->
        ResourceCapabilities = Resource#yawl_resource_persist.capabilities,
        lists:all(fun(Cap) ->
            lists:member(Cap, ResourceCapabilities)
        end, RequiredCapabilities)
    end, AllResources).

%% Match with capability levels (advanced)
find_resources_by_capability_level(RequiredCapabilities) ->
    {ok, AllResources} = yawl_persistence:list_resources(),

    lists:filtermap(fun(Resource) ->
        case match_capability_levels(
            RequiredCapabilities,
            Resource#yawl_resource_persist.capabilities
        ) of
            {ok, _} -> {true, Resource};
            no_match -> false
        end
    end, AllResources).

match_capability_levels(Required, Available) ->
    case Required -- Available of
        [] -> {ok, match};
        Missing -> {error, {missing_capabilities, Missing}}
    end.
```

## Allocation Strategies

### 1. Round Robin

```erlang
%% Round robin allocator
allocate_round_robin(RequiredCapabilities) ->
    case get_resources_by_capabilities(RequiredCapabilities) of
        [] ->
            {error, no_available_resources};
        Resources ->
            NextIndex = get_and_increment_round_robin_index(),
            SelectedIndex = NextIndex rem length(Resources) + 1,
            Resource = lists:nth(SelectedIndex, Resources),
            {ok, Resource}
    end.

%% Round robin state
-define(ROUND_ROBIN_KEY, yawl_round_robin_index).

get_round_robin_index() ->
    case persistent_term:get(?ROUND_ROBIN_KEY) of
        {ok, Index} -> Index;
        undefined -> 0
    end.

increment_round_robin_index() ->
    Index = get_round_robin_index(),
    persistent_term:put(?ROUND_ROBIN_KEY, Index + 1).
```

### 2. Least Loaded

```erlang
%% Least loaded allocator
allocate_least_loaded(RequiredCapabilities) ->
    case find_resources_by_capabilities(RequiredCapabilities) ->
        [] ->
            {error, no_available_resources};
        Resources ->
            %% Select resource with minimum current load
            BestResource = lists:foldl(fun(Resource, Best) ->
                Load = Resource#yawl_resource_persist.current_load,
                BestLoad = Best#yawl_resource_persist.current_load,
                case Load < BestLoad of
                    true -> Resource;
                    false -> Best
                end
            end, hd(Resources), tl(Resources)),
            {ok, BestResource}
    end.
```

### 3. Weighted Random

```erlang
%% Weighted random allocator
allocate_weighted_random(RequiredCapabilities) ->
    case find_resources_by_capabilities(RequiredCapabilities) of
        [] ->
            {error, no_available_resources};
        Resources ->
            %% Calculate weights based on available capacity
            Weights = lists:map(fun(Resource) ->
                Capacity = Resource#yawl_resource_persist.max_capacity,
                Load = Resource#yawl_resource_persist.current_load,
                Available = Capacity - Load,
                {Resource, max(Available, 0)}
            end, Resources),

            TotalWeight = lists:sum(fun({_, W}) -> W end, Weights),
            Random = rand:uniform() * TotalWeight,

            {SelectedResource, _} = select_weighted(Weights, Random, 0),
            {ok, SelectedResource}
    end.

select_weighted([{Resource, Weight} | Rest], Target, Acc) ->
    case Acc + Weight >= Target of
        true -> {Resource, Weight};
        false -> select_weighted(Rest, Target, Acc + Weight)
    end.
```

### 4. Priority-Based

```erlang
%% Priority-based allocator
allocate_by_priority(RequiredCapabilities, Priority) ->
    case find_resources_by_capabilities(RequiredCapabilities) of
        [] ->
            {error, no_available_resources};
        Resources ->
            %% Sort by resource priority
            SortedResources = lists:sort(fun(R1, R2) ->
                P1 = get_resource_priority(R1),
                P2 = get_resource_priority(R2),
                P1 >= P2
            end, Resources),

            %% Select highest priority resource with capacity
            select_by_priority_with_capacity(SortedResources, Priority)
    end.

select_by_priority_with_capacity([], _Priority) ->
    {error, no_resources_with_sufficient_priority};
select_by_priority_with_capacity([Resource | Rest], Priority) ->
    ResourcePriority = get_resource_priority(Resource),
    case ResourcePriority >= Priority of
        true ->
            case has_capacity(Resource) of
                true -> {ok, Resource};
                false -> select_by_priority_with_capacity(Rest, Priority)
            end;
        false ->
            select_by_priority_with_capacity(Rest, Priority)
    end.

get_resource_priority(Resource) ->
    maps:get(priority, Resource#yawl_resource_persist.attributes, 0).
```

## Allocation Workflow

### 1. Allocation Request

```erlang
%% Request resource allocation
allocate_resource(WorkitemId, RequiredCapabilities, Options) ->
    Strategy = maps:get(strategy, Options, round_robin),
    Priority = maps:get(priority, Options, 0),
    Timeout = maps:get(timeout, Options, 5000),

    %% Find suitable resources
    case find_and_allocate(WorkitemId, RequiredCapabilities, Strategy, Priority) of
        {ok, ResourceId, Allocation} ->
            %% Record allocation
            save_allocation(WorkitemId, ResourceId, Allocation),
            {ok, ResourceId, Allocation};
        {error, no_available_resources} ->
            %% Wait for resource to become available
            wait_for_resource(WorkitemId, RequiredCapabilities, Timeout);
        {error, Reason} ->
            {error, Reason}
    end.

find_and_allocate(WorkitemId, RequiredCapabilities, Strategy, Priority) ->
    %% Get available resources
    AvailableResources = get_available_resources_by_capabilities(
        RequiredCapabilities,
        Priority
    ),

    case AvailableResources of
        [] ->
            {error, no_available_resources};
        Resources ->
            %% Apply allocation strategy
            Resource = select_resource(Resources, Strategy),

            %% Create allocation record
            Allocation = #allocation{
                allocation_id = generate_id(),
                workitem_id = WorkitemId,
                resource_id = Resource#yawl_resource_persist.resource_id,
                allocated_at = erlang:monotonic_time(millisecond),
                status = active
            },

            %% Update resource load
            update_resource_load(
                Resource#yawl_resource_persist.resource_id,
                Resource#yawl_resource_persist.current_load + 1
            ),

            {ok, Resource#yawl_resource_persist.resource_id, Allocation}
    end.
```

### 2. Resource Release

```erlang
%% Release resource allocation
release_resource(WorkitemId, ResourceId, Result) ->
    case get_allocation(WorkitemId) of
        {ok, Allocation} ->
            %% Update allocation status
            update_allocation_status(Allocation, completed),

            %% Update resource load
            Resource = yawl_persistence:load_resource(ResourceId),
            NewLoad = Resource#yawl_resource_persist.current_load - 1,
            yawl_persistence:save_resource(
                Resource#yawl_resource_persist{current_load = NewLoad}
            ),

            %% Notify waiting workitems
            notify_resource_available(ResourceId),

            {ok, released};
        {error, Reason} ->
            {error, Reason}
    end.
```

### 3. Resource Waiting

```eraml
%% Wait for resource to become available
wait_for_resource(WorkitemId, RequiredCapabilities, Timeout) ->
    %% Add to waiting queue
    add_to_waiting_queue(WorkitemId, RequiredCapabilities),

    %% Wait for notification or timeout
    receive
        {resource_available, ResourceId} ->
            allocate_resource(WorkitemId, RequiredCapabilities, #{});
        {timeout, Timeout} ->
            remove_from_waiting_queue(WorkitemId),
            {error, allocation_timeout}
    after Timeout ->
        remove_from_waiting_queue(WorkitemId),
        {error, allocation_timeout}
    end.
```

## Advanced Features

### 1. Resource Pools

```erlang
%% Resource pool configuration
-record(resource_pool, {
    pool_id :: binary(),
    name :: binary(),
    capabilities :: [atom()],
    resources :: [binary()],
    allocation_strategy :: allocation_strategy(),
    min_size :: integer(),
    max_size :: integer(),
    current_size :: integer()
}).

%% Create resource pool
create_pool(PoolId, Config) ->
    Pool = #resource_pool{
        pool_id = PoolId,
        name = maps:get(name, Config),
        capabilities = maps:get(capabilities, Config),
        resources = [],
        allocation_strategy = maps:get(strategy, Config, round_robin),
        min_size = maps:get(min_size, Config, 1),
        max_size = maps:get(max_size, Config, 10),
        current_size = 0
    },
    save_pool(Pool).

%% Allocate from pool
allocate_from_pool(PoolId, WorkitemId, Options) ->
    {ok, Pool} = get_pool(PoolId),

    %% Select resource from pool using pool's strategy
    ResourceId = select_from_pool(
        Pool#resource_pool.resources,
        Pool#resource_pool.allocation_strategy
    ),

    allocate_resource(WorkitemId, ResourceId, Options).
```

### 2. Multi-Capability Allocation

```erlang
%% Allocate resources with multiple capabilities
allocate_multi_capability(WorkitemId, CapabilitySets, Options) ->
    %% Find resources that can handle all capabilities
    Allocations = lists:map(fun(Capabilities) ->
        allocate_resource(WorkitemId, Capabilities, Options)
    end, CapabilitySets),

    case lists:all(fun({Status, _}) -> Status =:= ok end, Allocations) of
        true ->
            {ok, [{ResourceId, _} || {ok, ResourceId, _} <- Allocations]};
        false ->
            %% Rollback any successful allocations
            lists:foreach(fun({ok, ResourceId, _}) ->
                release_resource(WorkitemId, ResourceId, rollback)
            end, Allocations),
            {error, partial_allocation_failed}
    end.
```

### 3. Resource Reservation

```erlang
%% Reserve resource for future workitem
reserve_resource(ResourceId, WorkitemId, StartTime, Duration) ->
    case check_availability(ResourceId, StartTime, Duration) of
        {ok, available} ->
            Reservation = #reservation{
                reservation_id = generate_id(),
                resource_id = ResourceId,
                workitem_id = WorkitemId,
                start_time = StartTime,
                duration = Duration,
                status = reserved
            },
            save_reservation(Reservation),
            {ok, Reservation};
        {error, Reason} ->
            {error, Reason}
    end.

%% Check resource availability
check_availability(ResourceId, StartTime, Duration) ->
    Resource = yawl_persistence:load_resource(ResourceId),
    CurrentLoad = Resource#yawl_resource_persist.current_load,
    MaxCapacity = Resource#yawl_resource_persist.max_capacity,

    ReservedAtTime = calculate_reserved_load(ResourceId, StartTime, Duration),

    case CurrentLoad + ReservedAtTime < MaxCapacity of
        true -> {ok, available};
        false -> {error, no_capacity}
    end.

calculate_reserved_load(ResourceId, StartTime, Duration) ->
    {ok, Reservations} = get_reservations(ResourceId),

    %% Count reservations overlapping with time window
    lists:foldl(fun(Reservation, Count) ->
        Overlaps = overlaps_time_window(
            Reservation,
            StartTime,
            Duration
        ),
        case Overlaps of
            true -> Count + 1;
            false -> Count
        end
    end, 0, Reservations).
```

### 4. Capability Leveling

```erlang
%% Capability levels
-define(CAPABILITY_LEVELS, #{
    approval => [junior, intermediate, senior, expert],
    review => [junior, intermediate, senior],
    technical_review => [senior, expert],
    payment_processing => [basic, advanced],
    data_processing => [standard, high_performance]
}).

%% Match capability levels
match_capability_levels(Required, Available) ->
    lists:map(fun({Capability, Level}) ->
        RequiredLevels = maps:get(Capability, ?CAPABILITY_LEVELS, [Level]),
        AvailableLevels = lists:filter(fun(L) ->
            lists:member(L, RequiredLevels)
        end, maps:get(Capability, Available, [])),
        case AvailableLevels of
            [] -> {error, {no_suitable_level, Capability}};
            _ ->
                %% Select highest available level
                [BestLevel | _] = lists:reverse(AvailableLevels),
                {ok, {Capability, BestLevel}}
        end
    end, Required).
```

## Resource Discovery

### 1. Capability Indexing

```erlang
%% Capability to resources index
-type capability_index() :: #{capability() => [resource_id()]}.

%% Build capability index
build_capability_index() ->
    {ok, Resources} = yawl_persistence:list_resources(),

    lists:foldl(fun(Resource, Index) ->
        Capabilities = Resource#yawl_resource_persist.capabilities,
        ResourceId = Resource#yawl_resource_persist.resource_id,

        lists:foldl(fun(Capability, Acc) ->
            Existing = maps:get(Capability, Acc, []),
            Acc#{Capability => [ResourceId | Existing]}
        end, Index, Capabilities)
    end, #{}, Resources).

%% Query capability index
get_resources_with_capability(Capability, Index) ->
    maps:get(Capability, Index, []).

%% Query multiple capabilities (AND)
get_resources_with_all_capabilities(Capabilities, Index) ->
    ResourceLists = [maps:get(C, Index, []) || C <- Capabilities],
    lists:usort(lists:foldl(fun(List, Acc) ->
        lists:filter(fun(R) -> lists:member(R, Acc) end, List)
    end, hd(ResourceLists), tl(ResourceLists)).

%% Query multiple capabilities (OR)
get_resources_with_any_capability(Capabilities, Index) ->
    lists:usort(lists:flatmap(fun(C) ->
        maps:get(C, Index, [])
    end, Capabilities)).
```

### 2. Real-Time Availability

```erlang
%% Track resource availability in real-time
track_availability() ->
    spawn(fun() -> availability_loop() end).

availability_loop() ->
    {ok, Resources} = yawl_persistence:list_resources(),

    %% Check each resource's availability
    lists:foreach(fun(Resource) ->
        ResourceId = Resource#yawl_resource_persist.resource_id,
        Availability = check_real_time_availability(Resource),

        %% Update availability cache
        update_availability_cache(ResourceId, Availability),

        %% Notify if status changed
        case availability_changed(ResourceId, Availability) of
            true -> notify_availability_change(ResourceId, Availability);
            false -> ok
        end
    end, Resources),

    %% Repeat after interval
    timer:sleep(?AVAILABILITY_CHECK_INTERVAL),
    availability_loop().

check_real_time_availability(Resource) ->
    %% Combine static status with real-time factors
    StaticStatus = Resource#yawl_resource_persist.status,
    Load = Resource#yawl_resource_persist.current_load,
    Capacity = Resource#yawl_resource_persist.max_capacity,
    LastHeartbeat = Resource#yawl_resource_persist.last_heartbeat,

    Now = erlang:monotonic_time(millisecond),
    HeartbeatAge = Now - LastHeartbeat,

    case {StaticStatus, HeartbeatAge} of
        {available, Age} when Age < ?HEARTBEAT_TIMEOUT ->
            case Load < Capacity of
                true -> available;
                false -> {unavailable, at_capacity}
            end;
        {available, _} ->
            {unavailable, stale_heartbeat};
        {Status, _} ->
            {unavailable, Status}
    end.
```

## Monitoring and Analytics

### 1. Utilization Metrics

```erlang
%% Calculate resource utilization
calculate_utilization(ResourceId) ->
    {ok, Resource} = yawl_persistence:load_resource(ResourceId),

    Load = Resource#yawl_resource_persist.current_load,
    Capacity = Resource#yawl_resource_persist.max_capacity,

    Utilization = case Capacity of
        0 -> 0;
        _ -> (Load / Capacity) * 100
    end,

    #{
        resource_id => ResourceId,
        current_load => Load,
        max_capacity => Capacity,
        utilization_percent => Utilization,
        status => Resource#yawl_resource_persist.status
    }.

%% Get utilization across all resources
get_utilization_report() ->
    {ok, Resources} = yawl_persistence:list_resources(),

    Report = lists:map(fun(Resource) ->
        calculate_utilization(Resource#yawl_resource_persist.resource_id)
    end, Resources),

    #{
        timestamp => erlang:system_time(millisecond),
        resources => Report,
        summary => calculate_utilization_summary(Report)
    }.

calculate_utilization_summary(UtilizationReports) ->
    TotalUtil = lists:sum(fun(R) ->
        maps:get(utilization_percent, R, 0)
    end, UtilizationReports),
    Count = length(UtilizationReports),

    case Count of
        0 -> #{average => 0, total => 0, count => 0};
        _ -> #{
            average => TotalUtil / Count,
            total => TotalUtil,
            count => Count
        }
    end.
```

### 2. Allocation Analytics

```erlang
%% Allocation statistics
get_allocation_statistics() ->
    {ok, Allocations} = get_all_allocations(),

    %% Group by resource
    ByResource = lists:foldl(fun(Allocation, Acc) ->
        ResourceId = Allocation#allocation.resource_id,
        Existing = maps:get(ResourceId, Acc, []),
        Acc#{ResourceId => [Allocation | Existing]}
    end, #{}, Allocations),

    %% Calculate statistics
    maps:map(fun(ResourceId, Allocs) ->
        #{
            resource_id => ResourceId,
            total_allocations => length(Allocs),
            active_allocations => count_active(Allocs),
            completed_allocations => count_completed(Allocs),
            failed_allocations => count_failed(Allocs),
            average_duration => average_allocation_duration(Allocs)
        }
    end, ByResource).

count_active(Allocations) ->
    length([A || A <- Allocations, A#allocation.status =:= active]).
count_completed(Allocations) ->
    length([A || A <- Allocations, A#allocation.status =:= completed]).
count_failed(Allocations) ->
    length([A || A <- Allocations, A#allocation.status =:= failed]).
```

### 3. Performance Metrics

```erlang
%% Resource performance metrics
get_performance_metrics(ResourceId) ->
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    {ok, Allocations} = get_resource_allocations(ResourceId),

    #{
        resource_id => ResourceId,
        throughput => calculate_throughput(Allocations),
        average_completion_time => calculate_avg_completion_time(Allocations),
        success_rate => calculate_success_rate(Allocations),
        current_queue_length => Resource#yawl_resource_persist.current_load,
        utilization_percentage => (Resource#yawl_resource_persist.current_load /
                                     Resource#yawl_resource_persist.max_capacity) * 100
    }.

calculate_throughput(Allocations) ->
    Completed = [A || A <- Allocations, A#allocation.status =:= completed],
    case Completed of
        [] -> 0;
        _ ->
            TimeWindow = ?THROUGHPUT_WINDOW,
            Now = erlang:monotonic_time(millisecond),
            Recent = [A || A <- Completed,
                          Now - A#allocation.completed_at < TimeWindow],
            length(Recent) / (TimeWindow / 1000)
    end.

calculate_avg_completion_time(Allocations) ->
    Completed = [A || A <- Allocations, A#allocation.status =:= completed],
    case Completed of
        [] -> 0;
        _ ->
            TotalTime = lists:foldl(fun(A, Sum) ->
                Duration = A#allocation.completed_at - A#allocation.allocated_at,
                Sum + Duration
            end, 0, Completed),
            TotalTime / length(Completed)
    end.
```

## Configuration

### Resource Manager Configuration

```erlang
%% Resource manager configuration
-record(rm_config, {
    allocation_strategy :: allocation_strategy(),
    allocation_timeout :: integer(),
    retry_policy :: map(),
    heartbeat_interval :: integer(),
    cleanup_interval :: integer()
}).

%% Default configuration
default_config() ->
    #rm_config{
        allocation_strategy = least_loaded,
        allocation_timeout = 30000,
        retry_policy => #{
            max_retries => 3,
            backoff => exponential,
            initial_delay => 1000
        },
        heartbeat_interval = 30000,
        cleanup_interval = 300000
    }.
```

---

Next: [Event Systems](event-systems.md) ->
