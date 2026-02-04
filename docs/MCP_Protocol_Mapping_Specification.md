# MCP Protocol Mapping Specification

## 1. Overview

This document specifies the detailed MCP (Model Context Protocol) mapping between Craftplan MCP, elrmcp, and A2A protocols. The mapping enables seamless bidirectional communication while maintaining protocol compatibility and consistency.

## 2. Protocol Mapping Architecture

### 2.1 Mapping Engine Architecture

```erlang
%% Core mapping data structures
-record(mcp_mapping, {
    id :: binary(),
    source_protocol :: atom(),
    target_protocol :: atom(),
    source_version :: binary(),
    target_version :: binary(),
    tools :: map(),
    resources :: map(),
    capabilities :: map(),
    transformation_rules :: map(),
    created_at :: binary(),
    updated_at :: binary()
}).

%% Tool mapping structure
-record(mcp_tool_mapping, {
    id :: binary(),
    source_tool :: binary(),
    target_tool :: binary(),
    mapping_type :: direct | composite | transformation,
    field_mappings :: map(),
    validation_rules :: list(),
    error_handling :: map(),
    version :: binary()
}).
```

### 2.2 Protocol Version Support

```yaml
Protocol Versions:
  - MCP 2024-11-05 (Current)
  - Custom elrmcp (Extended MCP)
  - A2A Protocol 1.0 (MCP-based)

Supported Mappings:
  - elrmcp → Craftplan MCP (Bidirectional)
  - Craftplan MCP → elrmcp (Bidirectional)
  - A2A → MCP Tools (Unidirectional)
  - MCP → A2A Skills (Unidirectional)
```

## 3. Tool Mapping Specifications

### 3.1 Customer Management Mapping

#### elrmcp → Craftplan MCP

```json
{
  "source_tool": "local_erp_customer",
  "target_tool": "customer_management",
  "mapping_type": "direct",
  "field_mappings": {
    "customer_id": "id",
    "customer_name": "name",
    "contact_email": "email",
    "contact_phone": "phone",
    "address_street": "address.street",
    "address_city": "address.city",
    "address_state": "address.state",
    "address_zip": "address.zip",
    "address_country": "address.country",
    "customer_type": "type",
    "credit_limit": "credit_limit",
    "tax_id": "tax_id",
    "created_at": "created_at",
    "updated_at": "updated_at"
  }
}
```

#### Craftplan MCP → elrmcp

```json
{
  "source_tool": "customer_management",
  "target_tool": "local_erp_customer",
  "mapping_type": "transformation",
  "field_mappings": {
    "id": "customer_id",
    "name": "customer_name",
    "email": "contact_email",
    "phone": "contact_phone",
    "address": {
      "street": "address_street",
      "city": "address_city",
      "state": "address_state",
      "zip": "address_zip",
      "country": "address_country"
    },
    "type": "customer_type",
    "credit_limit": "credit_limit",
    "tax_id": "tax_id",
    "created_at": "created_at",
    "updated_at": "updated_at"
  }
}
```

### 3.2 Order Management Mapping

#### elrmcp → Craftplan MCP

```json
{
  "source_tool": "local_erp_order",
  "target_tool": "order_management",
  "mapping_type": "transformation",
  "field_mappings": {
    "order_number": "order_id",
    "customer_id": "customer_id",
    "order_date": "order_date",
    "required_date": "required_date",
    "ship_date": "ship_date",
    "order_status": "status",
    "order_total": "total_amount",
    "order_tax": "tax_amount",
    "order_shipping": "shipping_amount",
    "order_discount": "discount_amount",
    "order_currency": "currency",
    "order_items": {
      "source_field": "order_lines",
      "transform": "order_line_to_item"
    },
    "shipping_address": "shipping_address",
    "billing_address": "billing_address",
    "payment_method": "payment_method",
    "payment_status": "payment_status",
    "created_by": "created_by",
    "updated_by": "updated_by",
    "created_at": "created_at",
    "updated_at": "updated_at"
  },
  "transformations": {
    "order_line_to_item": {
      "product_id": "item_number",
      "quantity": "quantity",
      "unit_price": "unit_price",
      "line_total": "line_total",
      "discount": "discount",
      "tax": "tax",
      "notes": "notes"
    }
  }
}
```

#### Craftplan MCP → elrmcp

```json
{
  "source_tool": "order_management",
  "target_tool": "local_erp_order",
  "mapping_type": "composite",
  "field_mappings": {
    "order_id": "order_number",
    "customer_id": "customer_id",
    "order_date": "order_date",
    "required_date": "required_date",
    "ship_date": "ship_date",
    "status": "order_status",
    "total_amount": "order_total",
    "tax_amount": "order_tax",
    "shipping_amount": "order_shipping",
    "discount_amount": "order_discount",
    "currency": "order_currency",
    "order_items": {
      "target_field": "order_lines",
      "transform": "item_to_order_line"
    },
    "shipping_address": "shipping_address",
    "billing_address": "billing_address",
    "payment_method": "payment_method",
    "payment_status": "payment_status",
    "created_by": "created_by",
    "updated_by": "updated_by",
    "created_at": "created_at",
    "updated_at": "updated_at"
  },
  "transformations": {
    "item_to_order_line": {
      "item_number": "product_id",
      "quantity": "quantity",
      "unit_price": "unit_price",
      "line_total": "line_total",
      "discount": "discount",
      "tax": "tax",
      "notes": "notes"
    }
  }
}
```

### 3.3 Inventory Management Mapping

#### elrmcp → Craftplan MCP

```json
{
  "source_tool": "local_erp_inventory",
  "target_tool": "inventory_management",
  "mapping_type": "transformation",
  "field_mappings": {
    "item_id": "product_id",
    "item_code": "sku",
    "item_name": "name",
    "item_description": "description",
    "category_id": "category_id",
    "category_name": "category_name",
    "unit_of_measure": "unit",
    "current_stock": "quantity",
    "reorder_level": "reorder_level",
    "maximum_stock": "max_stock",
    "minimum_stock": "min_stock",
    "average_cost": "cost",
    "selling_price": "price",
    "weight": "weight",
    "dimensions": "dimensions",
    "location": "warehouse_location",
    "bin_number": "bin_number",
    "supplier_id": "supplier_id",
    "supplier_name": "supplier_name",
    "lead_time": "lead_time",
    "last_count_date": "last_count_date",
    "last_purchase_date": "last_purchase_date",
    "last_sale_date": "last_sale_date",
    "status": "status",
    "created_at": "created_at",
    "updated_at": "updated_at"
  }
}
```

#### Craftplan MCP → elrmcp

```json
{
  "source_tool": "inventory_management",
  "target_tool": "local_erp_inventory",
  "mapping_type": "direct",
  "field_mappings": {
    "product_id": "item_id",
    "sku": "item_code",
    "name": "item_name",
    "description": "item_description",
    "category_id": "category_id",
    "category_name": "category_name",
    "unit": "unit_of_measure",
    "quantity": "current_stock",
    "reorder_level": "reorder_level",
    "max_stock": "maximum_stock",
    "min_stock": "minimum_stock",
    "cost": "average_cost",
    "price": "selling_price",
    "weight": "weight",
    "dimensions": "dimensions",
    "warehouse_location": "location",
    "bin_number": "bin_number",
    "supplier_id": "supplier_id",
    "supplier_name": "supplier_name",
    "lead_time": "lead_time",
    "last_count_date": "last_count_date",
    "last_purchase_date": "last_purchase_date",
    "last_sale_date": "last_sale_date",
    "status": "status",
    "created_at": "created_at",
    "updated_at": "updated_at"
  }
}
```

### 3.4 Production Planning Mapping

#### elrmcp → Craftplan MCP

```json
{
  "source_tool": "local_erp_production",
  "target_tool": "production_planning",
  "mapping_type": "composite",
  "field_mappings": {
    "production_order_id": "production_order_id",
    "work_order_number": "work_order_id",
    "production_order_number": "order_number",
    "customer_id": "customer_id",
    "product_id": "product_id",
    "product_name": "product_name",
    "quantity_required": "quantity_required",
    "quantity_completed": "quantity_completed",
    "quantity_scrapped": "quantity_scrapped",
    "production_status": "status",
    "planned_start_date": "planned_start_date",
    "planned_completion_date": "planned_completion_date",
    "actual_start_date": "actual_start_date",
    "actual_completion_date": "actual_completion_date",
    "work_center_id": "work_center_id",
    "work_center_name": "work_center_name",
    "routing_id": "routing_id",
    "routing_name": "routing_name",
    "priority": "priority",
    "due_date": "due_date",
    "created_by": "created_by",
    "updated_by": "updated_by",
    "created_at": "created_at",
    "updated_at": "updated_at"
  }
}
```

#### Craftplan MCP → elrmcp

```json
{
  "source_tool": "production_planning",
  "target_tool": "local_erp_production",
  "mapping_type": "transformation",
  "field_mappings": {
    "production_order_id": "production_order_id",
    "work_order_id": "work_order_number",
    "order_number": "production_order_number",
    "customer_id": "customer_id",
    "product_id": "product_id",
    "product_name": "product_name",
    "quantity_required": "quantity_required",
    "quantity_completed": "quantity_completed",
    "quantity_scrapped": "quantity_scrapped",
    "status": "production_status",
    "planned_start_date": "planned_start_date",
    "planned_completion_date": "planned_completion_date",
    "actual_start_date": "actual_start_date",
    "actual_completion_date": "actual_completion_date",
    "work_center_id": "work_center_id",
    "work_center_name": "work_center_name",
    "routing_id": "routing_id",
    "routing_name": "routing_name",
    "priority": "priority",
    "due_date": "due_date",
    "created_by": "created_by",
    "updated_by": "updated_by",
    "created_at": "created_at",
    "updated_at": "updated_at"
  }
}
```

### 3.5 Analytics Mapping

#### elrmcp → Craftplan MCP

```json
{
  "source_tool": "local_erp_analytics",
  "target_tool": "analytics",
  "mapping_type": "transformation",
  "field_mappings": {
    "report_type": {
      "source_field": "report_name",
      "transform": "report_name_to_type"
    },
    "date_range": "date_range",
    "filter_criteria": "filters",
    "data_source": "source_system",
    "aggregation_level": "aggregation",
    "metrics": {
      "source_field": "measures",
      "transform": "measure_to_metric"
    },
    "dimensions": "dimensions",
    "format": "output_format",
    "timezone": "timezone"
  },
  "transformations": {
    "report_name_to_type": {
      "sales_summary": "sales_summary",
      "profit_loss": "profit_loss",
      "customer_analysis": "customer_analysis",
      "product_analysis": "product_analysis",
      "inventory_analysis": "inventory_analysis",
      "production_analysis": "production_analysis"
    },
    "measure_to_metric": {
      "total_sales": "revenue",
      "total_profit": "profit",
      "total_orders": "orders",
      "total_customers": "customers",
      "total_products": "products",
      "inventory_value": "inventory_value",
      "production_efficiency": "efficiency"
    }
  }
}
```

#### Craftplan MCP → elrmcp

```json
{
  "source_tool": "analytics",
  "target_tool": "local_erp_analytics",
  "mapping_type": "composite",
  "field_mappings": {
    "report_type": {
      "target_field": "report_name",
      "transform": "type_to_report_name"
    },
    "date_range": "date_range",
    "filters": "filter_criteria",
    "source_system": "data_source",
    "aggregation": "aggregation_level",
    "metrics": {
      "target_field": "measures",
      "transform": "metric_to_measure"
    },
    "dimensions": "dimensions",
    "output_format": "format",
    "timezone": "timezone"
  },
  "transformations": {
    "type_to_report_name": {
      "sales_summary": "sales_summary",
      "profit_loss": "profit_loss",
      "customer_analysis": "customer_analysis",
      "product_analysis": "product_analysis",
      "inventory_analysis": "inventory_analysis",
      "production_analysis": "production_analysis"
    },
    "metric_to_measure": {
      "revenue": "total_sales",
      "profit": "total_profit",
      "orders": "total_orders",
      "customers": "total_customers",
      "products": "total_products",
      "inventory_value": "inventory_value",
      "efficiency": "production_efficiency"
    }
  }
}
```

### 3.6 Shipping Mapping

#### elrmcp → Craftplan MCP

```json
{
  "source_tool": "local_erp_shipping",
  "target_tool": "shipping",
  "mapping_type": "direct",
  "field_mappings": {
    "shipment_id": "shipment_id",
    "tracking_number": "tracking_number",
    "order_id": "order_id",
    "customer_id": "customer_id",
    "carrier_id": "carrier_id",
    "carrier_name": "carrier_name",
    "service_level": "service_level",
    "shipment_date": "shipment_date",
    "delivery_date": "delivery_date",
    "estimated_delivery": "estimated_delivery_date",
    "actual_delivery": "actual_delivery_date",
    "weight": "weight",
    "dimensions": "dimensions",
    "freight_cost": "freight_cost",
    "insurance_cost": "insurance_cost",
    "total_cost": "total_cost",
    "shipping_status": "status",
    "origin": "origin_address",
    "destination": "destination_address",
    "special_instructions": "instructions",
    "created_at": "created_at",
    "updated_at": "updated_at"
  }
}
```

#### Craftplan MCP → elrmcp

```json
{
  "source_tool": "shipping",
  "target_tool": "local_erp_shipping",
  "mapping_type": "direct",
  "field_mappings": {
    "shipment_id": "shipment_id",
    "tracking_number": "tracking_number",
    "order_id": "order_id",
    "customer_id": "customer_id",
    "carrier_id": "carrier_id",
    "carrier_name": "carrier_name",
    "service_level": "service_level",
    "shipment_date": "shipment_date",
    "delivery_date": "delivery_date",
    "estimated_delivery_date": "estimated_delivery",
    "actual_delivery_date": "actual_delivery",
    "weight": "weight",
    "dimensions": "dimensions",
    "freight_cost": "freight_cost",
    "insurance_cost": "insurance_cost",
    "total_cost": "total_cost",
    "status": "shipping_status",
    "origin_address": "origin",
    "destination_address": "destination",
    "instructions": "special_instructions",
    "created_at": "created_at",
    "updated_at": "updated_at"
  }
}
```

## 4. A2A Protocol Mapping

### 4.1 A2A → MCP Tools Mapping

```json
{
  "source_protocol": "a2a",
  "target_protocol": "mcp",
  "mapping_type": "task_to_tool",
  "field_mappings": {
    "task_type": {
      "source_field": "task_type",
      "transform": "task_to_tool_mapping"
    },
    "task_params": "arguments",
    "task_id": "request_id",
    "agent_id": "source_agent",
    "priority": "priority",
    "timeout": "timeout"
  },
  "transformations": {
    "task_to_tool_mapping": {
      "customer_management": "customer_management",
      "order_management": "order_management",
      "inventory_management": "inventory_management",
      "production_planning": "production_planning",
      "analytics": "analytics",
      "shipping": "shipping"
    }
  }
}
```

### 4.2 MCP → A2A Skills Mapping

```json
{
  "source_protocol": "mcp",
  "target_protocol": "a2a",
  "mapping_type": "tool_to_task",
  "field_mappings": {
    "tool_name": {
      "target_field": "task_type",
      "transform": "tool_to_task_mapping"
    },
    "tool_arguments": "task_params",
    "request_id": "task_id",
    "source_agent": "agent_id",
    "priority": "priority",
    "timeout": "timeout"
  },
  "transformations": {
    "tool_to_task_mapping": {
      "customer_management": "customer_management",
      "order_management": "order_management",
      "inventory_management": "inventory_management",
      "production_planning": "production_planning",
      "analytics": "analytics",
      "shipping": "shipping"
    }
  }
}
```

## 5. Request/Response Transformation Examples

### 5.1 elrmcp → Craftplan MCP Transformation

#### Request Transformation

```json
// Original elrmcp request
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "local_erp_customer",
    "arguments": {
      "operation": "list",
      "limit": 50,
      "filter": {
        "customer_type": "active"
      }
    }
  },
  "id": 1
}

// Transformed Craftplan MCP request
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "customer_management",
    "arguments": {
      "operation": "list",
      "limit": 50,
      "filter": {
        "type": "active"
      }
    }
  },
  "id": 1
}
```

#### Response Transformation

```json
// Original Craftplan MCP response
{
  "jsonrpc": "2.0",
  "result": {
    "customers": [
      {
        "id": "cust_001",
        "name": "John Doe",
        "email": "john@example.com",
        "phone": "+1-555-1234",
        "address": {
          "street": "123 Main St",
          "city": "New York",
          "state": "NY",
          "zip": "10001",
          "country": "USA"
        },
        "type": "active",
        "credit_limit": 10000,
        "created_at": "2024-01-01T00:00:00Z",
        "updated_at": "2024-01-15T00:00:00Z"
      }
    ],
    "total": 1,
    "limit": 50
  },
  "id": 1
}

// Transformed elrmcp response
{
  "jsonrpc": "2.0",
  "result": {
    "customers": [
      {
        "customer_id": "cust_001",
        "customer_name": "John Doe",
        "contact_email": "john@example.com",
        "contact_phone": "+1-555-1234",
        "address_street": "123 Main St",
        "address_city": "New York",
        "address_state": "NY",
        "address_zip": "10001",
        "address_country": "USA",
        "customer_type": "active",
        "credit_limit": 10000,
        "created_at": "2024-01-01T00:00:00Z",
        "updated_at": "2024-01-15T00:00:00Z"
      }
    ],
    "total": 1,
    "limit": 50
  },
  "id": 1
}
```

### 5.2 A2A → MCP Tools Transformation

#### Request Transformation

```json
// Original A2A task request
{
  "jsonrpc": "2.0",
  "method": "task.submit",
  "params": {
    "task_type": "order_management",
    "params": {
      "operation": "create",
      "order_data": {
        "customer_id": "cust_123",
        "items": [
          {
            "product_id": "prod_456",
            "quantity": 2
          }
        ]
      }
    },
    "priority": "normal",
    "timeout": 30000
  },
  "id": "task_001"
}

// Transformed MCP tool request
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "order_management",
    "arguments": {
      "operation": "create",
      "order_data": {
        "customer_id": "cust_123",
        "items": [
          {
            "product_id": "prod_456",
            "quantity": 2
          }
        ]
      }
    }
  },
  "id": "task_001"
}
```

#### Response Transformation

```json
// Original MCP tool response
{
  "jsonrpc": "2.0",
  "result": {
    "order_id": "ord_789",
    "status": "created",
    "total_amount": 99.99,
    "created_at": "2024-01-20T10:00:00Z"
  },
  "id": "task_001"
}

// Transformed A2A task response
{
  "jsonrpc": "2.0",
  "result": {
    "task_id": "task_001",
    "status": "completed",
    "result": {
      "order_id": "ord_789",
      "status": "created",
      "total_amount": 99.99,
      "created_at": "2024-01-20T10:00:00Z"
    }
  }
}
```

## 6. Error Handling and Mapping

### 6.1 Error Code Mapping

```erlang
%% Error code mapping table
-define(ERROR_MAPPING, #{
    %% Common errors
    {mcp, invalid_request} => {elrmcp, 4001, "Invalid request format"},
    {mcp, method_not_found} => {elrmcp, 4002, "Method not found"},
    {mcp, invalid_params} => {elrmcp, 4003, "Invalid parameters"},
    {mcp, internal_error} => {elrmcp, 5001, "Internal server error"},

    %% Authentication errors
    {mcp, unauthorized} => {elrmcp, 4011, "Unauthorized access"},
    {mcp, forbidden} => {elrmcp, 4012, "Access forbidden"},

    %% Business logic errors
    {mcp, customer_not_found} => {elrmcp, 4004, "Customer not found"},
    {mcp, order_not_found} => {elrmcp, 4005, "Order not found"},
    {mcp, insufficient_stock} => {elrmcp, 4006, "Insufficient stock"},
    {mcp, invalid_status} => {elrmcp, 4007, "Invalid status"},

    %% System errors
    {mcp, service_unavailable} => {elrmcp, 5031, "Service unavailable"},
    {mcp, timeout} => {elrmcp, 5041, "Request timeout"}
}).
```

### 6.2 Error Transformation Examples

```json
// MCP error response
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32602,
    "message": "Invalid parameters",
    "data": {
      "field": "customer_id",
      "reason": "Customer ID is required"
    }
  },
  "id": 1
}

// Transformed elrmcp error response
{
  "jsonrpc": "2.0",
  "error": {
    "code": 4003,
    "message": "Invalid parameters",
    "data": {
      "field": "customer_id",
      "reason": "Customer ID is required",
      "original_error": {
        "code": -32602,
        "message": "Invalid parameters"
      }
    }
  },
  "id": 1
}
```

## 7. Performance Considerations

### 7.1 Caching Strategy

```erlang
%% Mapping cache configuration
-record(mapping_cache, {
    key :: binary(),
    mapping :: #mcp_mapping{},
    ttl :: integer(),
    created_at :: binary(),
    accessed_at :: binary()
}).

%% Cache size limits
-define(MAX_CACHE_SIZE, 1000).
-define(DEFAULT_CACHE_TTL, 300). % 5 minutes
-define(CACHE_CLEAN_INTERVAL, 60). % 1 minute
```

### 7.2 Batch Processing

```erlang
%% Batch transformation for multiple requests
batch_transform(SourceSystem, TargetSystem, Requests) ->
    %% Group requests by tool
    Grouped = group_requests_by_tool(Requests),

    %% Process each tool group
    Results = lists:map(fun({Tool, ToolRequests}) ->
        case get_mapping(SourceSystem, TargetSystem, Tool) of
            {ok, Mapping} ->
                Transformed = lists:map(fun(Request) ->
                    transform_request(Request, Mapping)
                end, ToolRequests),
                {Tool, Transformed};
            {error, Reason} ->
                {Tool, {error, Reason}}
        end
    end, Grouped),

    %% Flatten results
    lists:flatmap(fun({Tool, Transformed}) ->
        case Transformed of
            List when is_list(List) -> List;
            {error, Error} -> [{Tool, {error, Error}}]
        end
    end, Results).
```

### 7.3 Performance Metrics

```erlang
%% Performance tracking
-record(mapping_metrics, {
    total_transformations :: integer(),
    successful_transformations :: integer(),
    failed_transformations :: integer(),
    average_transform_time :: integer(),
    max_transform_time :: integer(),
    min_transform_time :: integer(),
    cache_hits :: integer(),
    cache_misses :: integer()
}).
```

## 8. Configuration and Management

### 8.1 Dynamic Configuration

```yaml
# mapping-config.yaml
default_mappings:
  elrmcp_to_craftplan:
    default_timeout: 30
    retry_attempts: 3
    cache_enabled: true

  craftplan_to_elrmcp:
    default_timeout: 30
    retry_attempts: 3
    cache_enabled: true

  a2a_to_mcp:
    default_timeout: 60
    retry_attempts: 2
    cache_enabled: false

  mcp_to_a2a:
    default_timeout: 60
    retry_attempts: 2
    cache_enabled: false

custom_mappings:
  - source_system: elrmcp
    target_system: craftplan
    source_tool: custom_customer_lookup
    target_tool: customer_management
    mapping_type: transformation
    field_mappings:
      lookup_id: customer_id
      lookup_type: search_type
    version: 1.0.0

validation_rules:
  required_fields:
    customer_management: [id, name, email]
    order_management: [order_id, customer_id, items]
    inventory_management: [product_id, quantity]
    production_planning: [production_order_id, product_id, quantity]
    analytics: [report_type, date_range]
    shipping: [shipment_id, order_id, carrier_id]

  field_validation:
    email: regex_pattern
    phone: regex_pattern
    zip_code: regex_pattern
```

### 8.2 Monitoring and Logging

```erlang
%% Transformation logging
log_transformation(SourceSystem, TargetSystem, Tool, Request, Response, Duration) ->
    LogEntry = #{
        source_system => SourceSystem,
        target_system => TargetSystem,
        tool => Tool,
        request_id => maps:get(<<"id">>, Request, null),
        status => case Response of
            {ok, _} -> "success";
            {error, _} -> "failed"
        end,
        duration => Duration,
        timestamp => erlang:timestamp(),
        request_size => byte_size(jiffy:encode(Request)),
        response_size => case Response of
            {ok, Resp} -> byte_size(jiffy:encode(Resp));
            {error, Err} -> byte_size(jiffy:encode(Err))
        end
    },

    %% Log to file and database
    logger:info("Transformation log: ~p", [LogEntry]),
    save_transformation_metrics(LogEntry).
```

## 9. Testing Strategy

### 9.1 Unit Tests

```erlang
%% Mapping unit tests
-include_lib("eunit/include/eunit.hrl").

customer_mapping_test() ->
    Mapping = #mcp_tool_mapping{
        id = "customer_001",
        source_tool = "local_erp_customer",
        target_tool = "customer_management",
        mapping_type = "direct",
        field_mappings = #{
            "customer_id" => "id",
            "customer_name" => "name",
            "contact_email" => "email"
        }
    },

    Request = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"tools/call">>,
        <<"params">> => #{
            <<"name">> => <<"local_erp_customer">>,
            <<"arguments">> => #{
                <<"operation">> => <<"list">>,
                <<"customer_id">> => <<"cust_123">>
            }
        }
    },

    Expected = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"tools/call">>,
        <<"params">> => #{
            <<"name">> => <<"customer_management">>,
            <<"arguments">> => #{
                <<"operation">> => <<"list">>,
                <<"id">> => <<"cust_123">>
            }
        }
    },

    {ok, Result} = transform_request(Request, Mapping),
    ?assertEqual(Expected, Result).
```

### 9.2 Integration Tests

```erlang
%% Integration tests for end-to-end workflow
integration_test() ->
    %% Start test services
    {ok, _} = start_test_services(),

    %% Create test client
    Client = create_test_client(),

    %% Test elrmcp → Craftplan transformation
    elrmcp_request = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"tools/call">>,
        <<"params">> => #{
            <<"name">> => <<"local_erp_customer">>,
            <<"arguments">> => #{
                <<"operation">> => <<"list">>,
                <<"limit">> => 10
            }
        },
        <<"id">> => 1
    },

    {ok, elrmcp_response} = Client:call(elrmcp_request),

    %% Test Craftplan → elrmcp transformation
    craftplan_request = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"tools/call">>,
        <<"params">> => #{
            <<"name">> => <<"customer_management">>,
            <<"arguments">> => #{
                <<"operation">> => <<"create">>,
                <<"customer_data">> => #{
                    <<"name">> => <<"Test Customer">>,
                    <<"email">> => <<"test@example.com">>
                }
            }
        },
        <<"id">> => 2
    },

    {ok, craftplan_response} = Client:call(craftplan_request),

    %% Cleanup
    cleanup_test_services().
```

### 9.3 Performance Tests

```erlang
%% Performance benchmarking
performance_test() ->
    %% Create test data
    TestRequests = generate_test_requests(1000),

    %% Benchmark elrmcp → Craftplan transformation
    {Time1, Result1} = timer:tc(fun() ->
        lists:map(fun(Request) ->
            transform(elrmcp, craftplan, Request)
        end, TestRequests)
    end),

    %% Benchmark Craftplan → elrmcp transformation
    {Time2, Result2} = timer:tc(fun() ->
        lists:map(fun(Request) ->
            transform(craftplan, elrmcp, Request)
        end, TestRequests)
    end),

    %% Calculate metrics
    Metrics = #{
        elrmcp_to_craftplan => #{
            total_time => Time1,
            avg_time => Time1 / length(TestRequests),
            throughput => length(TestRequests) / (Time1 / 1000000)
        },
        craftplan_to_elrmcp => #{
            total_time => Time2,
            avg_time => Time2 / length(TestRequests),
            throughput => length(TestRequests) / (Time2 / 1000000)
        }
    },

    %% Assert performance requirements
    ?assert(Metrics:elrmcp_to_craftplan.avg_time < 1000), % < 1ms
    ?assert(Metrics:craftplan_to_elrmcp.avg_time < 1000), % < 1ms
    ?assert(Metrics:elrmcp_to_craftplan.throughput > 100), % > 100 req/s
    ?assert(Metrics:craftplan_to_elrmcp.throughput > 100).  % > 100 req/s
```

## 10. Security Considerations

### 10.1 Data Transformation Security

```erlang
%% Sensitive data handling
handle_sensitive_data(Request, Mapping) ->
    %% Check for sensitive fields
    SensitiveFields = detect_sensitive_fields(Mapping),

    case lists:any(fun(Field) ->
        maps:is_key(Field, Request)
    end, SensitiveFields) of
        true ->
            %% Log and audit sensitive data handling
            log_sensitive_data(Request, Mapping),
            %% Apply masking if required
            masked_request = apply_data_masking(Request, Mapping),
            masked_request;
        false ->
            Request
    end.
```

### 10.2 Access Control

```erlang
%% Mapping access control
check_mapping_access(SourceSystem, TargetSystem, Tool, User) ->
    %% Check user permissions for mapping
    RequiredPermission = mapping_permission(SourceSystem, TargetSystem, Tool),

    case user_has_permission(User, RequiredPermission) of
        true ->
            allowed;
        false ->
            {error, access_denied}
    end.
```

## 11. Conclusion

This MCP Protocol Mapping Specification provides a comprehensive framework for transforming requests and responses between different MCP implementations. The mapping engine ensures seamless communication while maintaining data integrity and performance requirements.

### 11.1 Key Benefits

1. **Seamless Integration**: Automatic translation between MCP implementations
2. **Data Integrity**: Preserved data structure and relationships
3. **Performance Optimized**: Caching and batch processing
4. **Extensible**: Easy to add new mappings and transformations
5. **Secure**: Proper handling of sensitive data and access control
6. **Observable**: Comprehensive logging and monitoring

### 11.2 Implementation Checklist

- [ ] Implement mapping registry
- [ ] Create transformation engine
- [ ] Add caching layer
- [ ] Implement error handling
- [ ] Add monitoring and logging
- [ ] Create configuration management
- [ ] Implement security controls
- [ ] Write comprehensive tests
- [ ] Performance optimization
- [ ] Documentation

This specification provides a solid foundation for building a robust MCP protocol mapping system that can handle complex integration scenarios while maintaining performance and security requirements.