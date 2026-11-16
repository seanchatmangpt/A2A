# YAWL XES Export Examples

This document provides example XES exports from YAWL workflow executions, demonstrating how AI integration patterns are logged and exported.

## Table of Contents

1. [Simple Sequential Workflow](#simple-sequential-workflow)
2. [Parallel/Concurrent Workflow](#parallelconcurrent-workflow)
3. [Object-Centric Event Log (OCEL)](#object-centric-event-log-ocel)
4. [AI-Validated Workflow](#ai-validated-workflow)
5. [Multi-Instance Pattern](#multi-instance-pattern)

---

## Simple Sequential Workflow

This example shows a basic approval workflow with three sequential steps.

### Workflow Definition

```erlang
%% Sequential approval workflow
workflow_definition() ->
    #{
        workflow_id => <<"approval_wf">>,
        name => <<"Document Approval">>,
        activities => [
            {<<"Submit">>, #{
                type => task,
                executor => user
            }},
            {<<"Review">>, #{
                type => task,
                executor => manager
            }},
            {<<"Approve">>, #{
                type => task,
                executor => director
            }}
        ],
        flow => [
            {<<"Submit">>, <<"Review">>},
            {<<"Review">>, <<"Approve">>}
        ]
    }.
```

### XES Export Output

```xml
<?xml version="1.0" encoding="UTF-8"?>
<log xmlns="http://www.xes-standard.org/"
     xes.version="1.0"
     xes.features="nested-attributes"
     openxes.version="1.0RC7">
  <extension name="Concept" prefix="concept" uri="http://www.xes-standard.org/concept.xesext"/>
  <extension name="Lifecycle" prefix="lifecycle" uri="http://www.xes-standard.org/lifecycle.xesext"/>
  <extension name="Time" prefix="time" uri="http://www.xes-standard.org/time.xesext"/>
  <extension name="Organizational" prefix="org" uri="http://www.xes-standard.org/org.xesext"/>
  <extension name="YAWL" prefix="yawl" uri="http://a2a.org/yawl.xesext"/>

  <global scope="trace">
    <string key="concept:name" value="Case ID"/>
  </global>

  <global scope="event">
    <string key="concept:name" value="Activity"/>
    <string key="lifecycle:transition" value="complete"/>
    <date key="time:timestamp" value="1970-01-01T00:00:00.000+00:00"/>
  </global>

  <classifier name="Activity" keys="concept:name"/>
  <classifier name="Lifecycle" keys="lifecycle:transition"/>

  <trace>
    <string key="concept:name" value="approval_wf_20250205_001"/>
    <string key="yawl:workflow_id" value="approval_wf"/>

    <event>
      <string key="concept:name" value="Submit"/>
      <string key="lifecycle:transition" value="complete"/>
      <date key="time:timestamp" value="2025-02-05T10:15:30.123+00:00"/>
      <string key="yawl:task_id" value="submit_task_001"/>
      <string key="org:resource" value="user_123"/>
      <string key="yawl:role" value="submitter"/>
    </event>

    <event>
      <string key="concept:name" value="Review"/>
      <string key="lifecycle:transition" value="complete"/>
      <date key="time:timestamp" value="2025-02-05T10:17:45.456+00:00"/>
      <string key="yawl:task_id" value="review_task_001"/>
      <string key="org:resource" value="manager_456"/>
      <string key="yawl:role" value="manager"/>
      <string key="yawl:decision" value="approved"/>
    </event>

    <event>
      <string key="concept:name" value="Approve"/>
      <string key="lifecycle:transition" value="complete"/>
      <date key="time:timestamp" value="2025-02-05T10:22:10.789+00:00"/>
      <string key="yawl:task_id" value="approve_task_001"/>
      <string key="org:resource" value="director_789"/>
      <string key="yawl:role" value="director"/>
    </event>
  </trace>
</log>
```

---

## Parallel/Concurrent Workflow

This example demonstrates the AND-split pattern where multiple activities execute concurrently.

### Workflow Definition

```erlang
parallel_workflow() ->
    #{
        workflow_id => <<"parallel_processing">>,
        name => <<"Document Processing Pipeline">>,
        activities => [
            {<<"Start">>, #{type => task}},
            {<<"Validate">>, #{type => task}},
            {<<"Translate">>, #{type => task}},
            {<<"Format">>, #{type => task}},
            {<<"End">>, #{type => task}}
        ],
        flow => [
            {<<"Start">>, <<"Validate">>},
            {<<"Validate">>, <<"Translate">>},
            {<<"Validate">>, <<"Format">>},  % Parallel branch
            {<<"Translate">>, <<"End">>},
            {<<"Format">>, <<"End">>}       % Merge
        ]
    }.
```

### XES Export with Partial Order

```xml
<?xml version="1.0" encoding="UTF-8"?>
<log xmlns="http://www.xes-standard.org/"
     xes.version="1.0"
     xes.features="nested-attributes">
  <extension name="Concept" prefix="concept" uri="http://www.xes-standard.org/concept.xesext"/>
  <extension name="Lifecycle" prefix="lifecycle" uri="http://www.xes-standard.org/lifecycle.xesext"/>
  <extension name="Time" prefix="time" uri="http://www.xes-standard.org/time.xesext"/>
  <extension name="PartialOrder" prefix="po" uri="http://www.xes-standard.org/partial-order.xesext"/>

  <trace>
    <string key="concept:name" value="parallel_processing_001"/>
    <string key="yawl:pattern" value="AND-split"/>

    <event>
      <string key="concept:name" value="Start"/>
      <date key="time:timestamp" value="2025-02-05T14:00:00.000+00:00"/>
      <string key="po:successors" value="Validate"/>
    </event>

    <event>
      <string key="concept:name" value="Validate"/>
      <date key="time:timestamp" value="2025-02-05T14:01:00.000+00:00"/>
      <string key="po:successors" value="Translate,Format"/>
    </event>

    <!-- Concurrent activities - order not guaranteed -->
    <event>
      <string key="concept:name" value="Translate"/>
      <date key="time:timestamp" value="2025-02-05T14:02:30.000+00:00"/>
      <string key="po:concurrent-with" value="Format"/>
      <string key="po:successors" value="End"/>
    </event>

    <event>
      <string key="concept:name" value="Format"/>
      <date key="time:timestamp" value="2025-02-05T14:02:15.000+00:00"/>
      <string key="po:concurrent-with" value="Translate"/>
      <string key="po:successors" value="End"/>
    </event>

    <event>
      <string key="concept:name" value="End"/>
      <date key="time:timestamp" value="2025-02-05T14:05:00.000+00:00"/>
    </event>
  </trace>
</log>
```

---

## Object-Centric Event Log (OCEL)

This example shows an OCEL export from an order processing workflow involving multiple object types.

### OCEL XES Export

```xml
<?xml version="1.0" encoding="UTF-8"?>
<log xmlns="http://www.xes-standard.org/"
     xes.version="1.0"
     xes.features="nested-attributes">
  <extension name="OCEL" prefix="ocel" uri="http://www.ocel-standard.org/ocel.xesext"/>
  <extension name="Concept" prefix="concept" uri="http://www.xes-standard.org/concept.xesext"/>

  <string key="ocel:version" value="1.0"/>
  <string key="ocel:object-types" value="Order,Customer,Item,Payment"/>

  <!-- Object type definitions -->
  <classifier name="Order" keys="ocel:order-id"/>
  <classifier name="Customer" keys="ocel:customer-id"/>
  <classifier name="Item" keys="ocel:item-id"/>
  <classifier name="Payment" keys="ocel:payment-id"/>

  <trace>
    <string key="concept:name" value="order_lifecycle_001"/>
    <string key="ocel:object-type" value="Order"/>
    <string key="ocel:object-id" value="order_12345"/>

    <!-- Order creation event -->
    <event>
      <string key="concept:name" value="CreateOrder"/>
      <date key="time:timestamp" value="2025-02-05T09:00:00.000+00:00"/>
      <string key="ocel:objects-order" value="order_12345"/>
      <string key="ocel:objects-customer" value="customer_001"/>
      <float key="amount" value="250.00"/>
    </event>

    <!-- Add items to order -->
    <event>
      <string key="concept:name" value="AddItem"/>
      <date key="time:timestamp" value="2025-02-05T09:01:30.000+00:00"/>
      <string key="ocel:objects-order" value="order_12345"/>
      <string key="ocel:objects-item" value="item_A001"/>
      <int key="quantity" value="2"/>
    </event>

    <event>
      <string key="concept:name" value="AddItem"/>
      <date key="time:timestamp" value="2025-02-05T09:02:00.000+00:00"/>
      <string key="ocel:objects-order" value="order_12345"/>
      <string key="ocel:objects-item" value="item_B002"/>
      <int key="quantity" value="1"/>
    </event>

    <!-- Multi-object payment event -->
    <event>
      <string key="concept:name" value="ProcessPayment"/>
      <date key="time:timestamp" value="2025-02-05T09:05:00.000+00:00"/>
      <string key="ocel:objects-order" value="order_12345"/>
      <string key="ocel:objects-payment" value="payment_P001"/>
      <string key="ocel:objects-customer" value="customer_001"/>
      <string key="payment-method" value="credit_card"/>
      <float key="amount" value="250.00"/>
    </event>

    <!-- Shipping involves order and items -->
    <event>
      <string key="concept:name" value="ShipItems"/>
      <date key="time:timestamp" value="2025-02-05T09:10:00.000+00:00"/>
      <string key="ocel:objects-order" value="order_12345"/>
      <string key="ocel:objects-item" value="item_A001,item_B002"/>
      <string key="shipping-carrier" value="FedEx"/>
    </event>
  </trace>
</log>
```

---

## AI-Validated Workflow

This example shows a workflow execution where LLM validation results are embedded in the XES log.

### AI Validation Workflow

```erlang
%% Execute workflow with AI validation
execute_with_ai_validation() ->
    WorkflowId = <<"ai_validated_wf">>,
    {ok, LogId} = yawl_xes_logger:create_trace(WorkflowId),

    %% Log events with AI metadata
    ok = yawl_xes_logger:log_workflow_event(
        WorkflowId,
        <<"GenerateProcess">>,
        complete,
        #{
            <<"ai_model">> => <<"gpt-4">>,
            <<"ai_confidence">> => 0.92,
            <<"ai_grounding_score">> => 0.88
        }
    ),

    %% Validate AI output
    ValidationResult = yawl_llm_validator:validate_against_xes(
        AIModel,
        XESLog
    ),

    %% Log validation results
    ok = yawl_xes_logger:log_workflow_event(
        WorkflowId,
        <<"ValidateAI">>,
        complete,
        #{
            <<"validation_passed">> => maps:get(is_valid, ValidationResult),
            <<"fidelity_score">> => maps:get(fidelity_score, ValidationResult),
            <<"hallucinations_detected">> => length(maps:get(contradictions, ValidationResult, []))
        }
    ).
```

### XES Export with AI Metadata

```xml
<?xml version="1.0" encoding="UTF-8"?>
<log xmlns="http://www.xes-standard.org/"
     xes.version="1.0"
     xes.features="nested-attributes">
  <extension name="AI" prefix="ai" uri="http://a2a.org/ai.xesext"/>
  <extension name="Concept" prefix="concept" uri="http://www.xes-standard.org/concept.xesext"/>

  <trace>
    <string key="concept:name" value="ai_validated_wf_001"/>
    <string key="ai:model" value="gpt-4"/>
    <string key="ai:validation_status" value="validated"/>

    <!-- AI-generated process model -->
    <event>
      <string key="concept:name" value="GenerateProcess"/>
      <date key="time:timestamp" value="2025-02-05T11:00:00.000+00:00"/>
      <string key="ai:model" value="gpt-4"/>
      <float key="ai:confidence" value="0.92"/>
      <float key="ai:grounding_score" value="0.88"/>
      <string key="ai:ocpm_supported" value="true"/>
    </event>

    <!-- Validation results -->
    <event>
      <string key="concept:name" value="ValidateAI"/>
      <date key="time:timestamp" value="2025-02-05T11:00:05.000+00:00"/>
      <boolean key="ai:validation_passed" value="true"/>
      <float key="ai:fidelity_score" value="0.87"/>
      <int key="ai:hallucinations_detected" value="0"/>
      <int key="ai:missing_activities" value="0"/>
      <int key="ai:spurious_activities" value="0"/>
      <list key="ai:validation_details">
        <string>Structural match: 95%</string>
        <string>Behavioral match: 87%</string>
        <string>Temporal consistency: 92%</string>
      </list>
    </event>

    <!-- Grounding evidence -->
    <event>
      <string key="concept:name" value="GroundingEvidence"/>
      <date key="time:timestamp" value="2025-02-05T11:00:10.000+00:00"/>
      <int key="ai:evidence_count" value="47"/>
      <int key="ai:temporal_patterns" value="8"/>
      <int key="ai:action_patterns" value="12"/>
      <float key="ai:grounding_confidence" value="0.91"/>
    </event>
  </trace>
</log>
```

---

## Multi-Instance Pattern

This example shows the multi-instance pattern (for-each loop) with dynamic instance creation.

### Multi-Instance Workflow

```erlang
multi_instance_workflow() ->
    #{
        workflow_id => <<"batch_processing">>,
        name => <<"Batch Document Processing">>,
        activities => [
            {<<"Initialize">>, #{
                type => task,
                mode => single
            }},
            {<<"ProcessItem">>, #{
                type => task,
                mode => foreach,
                collection => <<"items">>
            }},
            {<<"Finalize">>, #{
                type => task,
                mode => single
            }}
        ],
        flow => [
            {<<"Initialize">>, <<"ProcessItem">>},
            {<<"ProcessItem">>, <<"Finalize">>}
        ]
    }.
```

### XES Export for Multi-Instance

```xml
<?xml version="1.0" encoding="UTF-8"?>
<log xmlns="http://www.xes-standard.org/"
     xes.version="1.0"
     xes.features="nested-attributes">
  <extension name="YAWL" prefix="yawl" uri="http://a2a.org/yawl.xesext"/>
  <extension name="Concept" prefix="concept" uri="http://www.xes-standard.org/concept.xesext"/>

  <trace>
    <string key="concept:name" value="batch_processing_001"/>
    <string key="yawl:pattern" value="multi-instance"/>

    <!-- Initialize batch -->
    <event>
      <string key="concept:name" value="Initialize"/>
      <date key="time:timestamp" value="2025-02-05T15:00:00.000+00:00"/>
      <int key="yawl:batch_size" value="5"/>
      <string key="yawl:collection" value="items"/>
    </event>

    <!-- Multiple instances of ProcessItem (potentially concurrent) -->
    <event>
      <string key="concept:name" value="ProcessItem"/>
      <date key="time:timestamp" value="2025-02-05T15:00:10.000+00:00"/>
      <string key="yawl:instance_id" value="ProcessItem_1"/>
      <string key="yawl:item_id" value="item_001"/>
      <string key="yawl:instance_state" value="started"/>
    </event>

    <event>
      <string key="concept:name" value="ProcessItem"/>
      <date key="time:timestamp" value="2025-02-05T15:00:11.000+00:00"/>
      <string key="yawl:instance_id" value="ProcessItem_2"/>
      <string key="yawl:item_id" value="item_002"/>
      <string key="yawl:instance_state" value="started"/>
    </event>

    <!-- Instance 1 completes -->
    <event>
      <string key="concept:name" value="ProcessItem"/>
      <date key="time:timestamp" value="2025-02-05T15:00:25.000+00:00"/>
      <string key="lifecycle:transition" value="complete"/>
      <string key="yawl:instance_id" value="ProcessItem_1"/>
      <string key="yawl:item_id" value="item_001"/>
      <string key="yawl:instance_state" value="completed"/>
    </event>

    <!-- Instance 2 completes -->
    <event>
      <string key="concept:name" value="ProcessItem"/>
      <date key="time:timestamp" value="2025-02-05T15:00:27.000+00:00"/>
      <string key="lifecycle:transition" value="complete"/>
      <string key="yawl:instance_id" value="ProcessItem_2"/>
      <string key="yawl:item_id" value="item_002"/>
      <string key="yawl:instance_state" value="completed"/>
    </event>

    <!-- More instances... -->

    <!-- Finalize after all instances complete -->
    <event>
      <string key="concept:name" value="Finalize"/>
      <date key="time:timestamp" value="2025-02-05T15:01:30.000+00:00"/>
      <int key="yawl:instances_completed" value="5"/>
      <int key="yawl:instances_total" value="5"/>
    </event>
  </trace>
</log>
```

---

## Usage Examples

### Reading XES Logs in Erlang

```erlang
%% Read and parse XES log
{ok, XESBinary} = file:read_file("workflow.xes"),
{ok, XESLog} = yawl_xes_formatter:parse_xes(XESBinary).

%% Extract activities for LLM training
Activities = [
    begin
        #xes_event{activity = A, timestamp = T} = E,
        #{activity => A, timestamp => T}
    end
    || E <- XESLog#xes_log.traces
].

%% Validate LLM model against XES log
LLMModel = #{
    activities => [<<"Submit">>, <<"Review">>, <<"Approve">>],
    transitions => [
        #{from => <<"Submit">>, to => <<"Review">>},
        #{from => <<"Review">>, to => <<"Approve">>}
    ]
},
ValidationResult = yawl_llm_validator:validate_against_xes(LLMModel, XESLog).
```

### Generating OCEL for AI Grounding

```erlang
%% Create OCEL log from workflow execution
{ok, OCELLogId} = yawl_ocpm:create_ocel_log(),

%% Log multi-object events
ok = yawl_ocpm:log_multi_object_event(
    #{<<"Order">> => [<<"order_123">>], <<"Item">> => [<<"item_456">>]},
    #{activity => <<"AddItem">>}
),

%% Ground generative AI output
GroundingResult = yawl_ocpm:ground_generative_ai(
    get_ocel_log(OCELLogId)
).

%% Use grounding score to validate AI predictions
case maps:get(grounded, GroundingResult) of
    true ->
        {ok, maps:get(confidence, GroundingResult)};
    false ->
        {error, insufficient_grounding}
end.
```

---

## References

- IEEE 1849-2016: XES Standard (eXtensible Event Stream)
- van der Aalst et al. (2025): Object-Centric Process Mining for Grounding AI
- van der Aalst et al. (2026): Reachability Analysis in Workflow Nets
- YAWL Pattern Documentation: See `/docs/yawl/patterns/`
