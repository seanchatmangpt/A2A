#!/bin/bash

################################################################################
# GCP Marketplace Metering Script
#
# Purpose: Track usage, report metrics to GCP Billing API, and handle cost allocation
# Usage: ./metering.sh [command] [options]
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/billing.yaml}"
LOG_DIR="${LOG_DIR:-/var/log/marketplace-billing}"
DATA_DIR="${DATA_DIR:-/var/lib/marketplace-billing}"
METRICS_FILE="${DATA_DIR}/metrics.db"
STATE_FILE="${DATA_DIR}/state.json"

# GCP Configuration
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_BILLING_ACCOUNT_ID="${GCP_BILLING_ACCOUNT_ID:-}"
GCP_SERVICE_ACCOUNT_KEY="${GCP_SERVICE_ACCOUNT_KEY_PATH:-}"
GCP_REGION="${GCP_REGION:-us-central1}"

# API Endpoints
BILLING_API_ENDPOINT="https://cloudbilling.googleapis.com/v1"
METERING_API_ENDPOINT="https://servicecontrol.googleapis.com/v1"
MONITORING_API_ENDPOINT="https://monitoring.googleapis.com/v3"

# Metering Configuration
REPORTING_INTERVAL="${REPORTING_INTERVAL:-3600}"  # 1 hour in seconds
BATCH_SIZE="${BATCH_SIZE:-1000}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"

# Logging Configuration
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_DIR}/metering-$(date +%Y%m%d).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# Utility Functions
################################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"

    # Send to Stackdriver if enabled
    if [[ "${ENABLE_STACKDRIVER_LOGGING:-false}" == "true" ]]; then
        send_to_stackdriver "${level}" "${message}"
    fi
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
    log "WARN" "$@"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    log "ERROR" "$@"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    log "INFO" "$@"
}

die() {
    log_error "$@"
    exit 1
}

# Initialize directories
init_dirs() {
    mkdir -p "${LOG_DIR}" "${DATA_DIR}"
    touch "${LOG_FILE}"
}

# Check prerequisites
check_prerequisites() {
    local missing=()

    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v gcloud >/dev/null 2>&1 || missing+=("gcloud")

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required tools: ${missing[*]}"
    fi

    if [[ -z "${GCP_PROJECT_ID}" ]]; then
        die "GCP_PROJECT_ID is not set"
    fi
}

################################################################################
# Authentication
################################################################################

get_access_token() {
    local token

    if [[ -n "${GCP_SERVICE_ACCOUNT_KEY}" && -f "${GCP_SERVICE_ACCOUNT_KEY}" ]]; then
        token=$(gcloud auth application-default print-access-token \
            --credential-file-override="${GCP_SERVICE_ACCOUNT_KEY}" 2>/dev/null)
    else
        token=$(gcloud auth application-default print-access-token 2>/dev/null)
    fi

    if [[ -z "${token}" ]]; then
        die "Failed to obtain access token"
    fi

    echo "${token}"
}

################################################################################
# Metrics Collection
################################################################################

# Collect API request metrics
collect_api_metrics() {
    log_info "Collecting API request metrics..."

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local metrics_json="${DATA_DIR}/api_metrics_${timestamp}.json"

    # Query from application logs or metrics system
    local api_requests=$(query_api_requests)
    local api_latency=$(query_api_latency)
    local api_errors=$(query_api_errors)

    cat > "${metrics_json}" <<EOF
{
  "timestamp": "${timestamp}",
  "metric_type": "api_requests",
  "metrics": {
    "total_requests": ${api_requests},
    "average_latency_ms": ${api_latency},
    "error_count": ${api_errors},
    "success_rate": $(echo "scale=4; (${api_requests} - ${api_errors}) / ${api_requests}" | bc)
  }
}
EOF

    echo "${metrics_json}"
}

# Collect compute metrics
collect_compute_metrics() {
    log_info "Collecting compute metrics..."

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local metrics_json="${DATA_DIR}/compute_metrics_${timestamp}.json"

    # Query GCE instances
    local instances=$(gcloud compute instances list \
        --project="${GCP_PROJECT_ID}" \
        --format=json 2>/dev/null || echo "[]")

    local total_hours=0
    local instance_count=$(echo "${instances}" | jq 'length')

    # Calculate compute hours
    if [[ ${instance_count} -gt 0 ]]; then
        total_hours=$(echo "${instances}" | jq -r '
            map(select(.status == "RUNNING")) |
            length
        ')
    fi

    cat > "${metrics_json}" <<EOF
{
  "timestamp": "${timestamp}",
  "metric_type": "compute_hours",
  "metrics": {
    "total_instances": ${instance_count},
    "running_instances": ${total_hours},
    "compute_hours": ${total_hours}
  }
}
EOF

    echo "${metrics_json}"
}

# Collect storage metrics
collect_storage_metrics() {
    log_info "Collecting storage metrics..."

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local metrics_json="${DATA_DIR}/storage_metrics_${timestamp}.json"

    # Query Cloud Storage buckets
    local buckets=$(gsutil ls -p "${GCP_PROJECT_ID}" 2>/dev/null || echo "")
    local total_bytes=0

    for bucket in ${buckets}; do
        local bucket_size=$(gsutil du -s "${bucket}" 2>/dev/null | awk '{print $1}' || echo "0")
        total_bytes=$((total_bytes + bucket_size))
    done

    cat > "${metrics_json}" <<EOF
{
  "timestamp": "${timestamp}",
  "metric_type": "storage_bytes",
  "metrics": {
    "total_bytes": ${total_bytes},
    "total_gb": $(echo "scale=2; ${total_bytes} / 1073741824" | bc),
    "bucket_count": $(echo "${buckets}" | wc -l)
  }
}
EOF

    echo "${metrics_json}"
}

# Collect network metrics
collect_network_metrics() {
    log_info "Collecting network metrics..."

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local metrics_json="${DATA_DIR}/network_metrics_${timestamp}.json"

    # Query network egress from Monitoring API
    local token=$(get_access_token)
    local end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local start_time=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")

    local egress_bytes=$(curl -s -X GET \
        "${MONITORING_API_ENDPOINT}/projects/${GCP_PROJECT_ID}/timeSeries" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d @- <<EOF | jq -r '.timeSeries[0].points[0].value.int64Value // 0'
{
  "filter": "metric.type=\"compute.googleapis.com/instance/network/sent_bytes_count\"",
  "interval": {
    "startTime": "${start_time}",
    "endTime": "${end_time}"
  },
  "aggregation": {
    "alignmentPeriod": "3600s",
    "perSeriesAligner": "ALIGN_SUM"
  }
}
EOF
)

    cat > "${metrics_json}" <<EOF
{
  "timestamp": "${timestamp}",
  "metric_type": "network_egress",
  "metrics": {
    "egress_bytes": ${egress_bytes},
    "egress_gb": $(echo "scale=2; ${egress_bytes} / 1073741824" | bc)
  }
}
EOF

    echo "${metrics_json}"
}

# Collect user seat metrics
collect_user_metrics() {
    log_info "Collecting user seat metrics..."

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local metrics_json="${DATA_DIR}/user_metrics_${timestamp}.json"

    # Query from user database or identity system
    local active_users=$(query_active_users)
    local total_seats=$(query_total_seats)

    cat > "${metrics_json}" <<EOF
{
  "timestamp": "${timestamp}",
  "metric_type": "user_seats",
  "metrics": {
    "active_users": ${active_users},
    "total_seats": ${total_seats},
    "utilization": $(echo "scale=4; ${active_users} / ${total_seats}" | bc)
  }
}
EOF

    echo "${metrics_json}"
}

# Aggregate all metrics
collect_all_metrics() {
    log_info "Starting metrics collection cycle..."

    local metrics=()

    metrics+=("$(collect_api_metrics)")
    metrics+=("$(collect_compute_metrics)")
    metrics+=("$(collect_storage_metrics)")
    metrics+=("$(collect_network_metrics)")
    metrics+=("$(collect_user_metrics)")

    # Combine into single report
    local combined_json="${DATA_DIR}/metrics_report_$(date +%s).json"
    jq -s '.' "${metrics[@]}" > "${combined_json}"

    log_success "Metrics collection complete: ${combined_json}"
    echo "${combined_json}"
}

################################################################################
# Usage Tracking Helpers
################################################################################

query_api_requests() {
    # Query from application metrics or logs
    # This is a placeholder - implement based on your metrics system
    echo "1000"
}

query_api_latency() {
    # Query average API latency
    echo "150"
}

query_api_errors() {
    # Query API error count
    echo "10"
}

query_active_users() {
    # Query active user count from database
    echo "50"
}

query_total_seats() {
    # Query total licensed seats
    echo "100"
}

################################################################################
# GCP Billing API Integration
################################################################################

# Submit usage to Service Control API
submit_usage_report() {
    local metrics_file=$1

    if [[ ! -f "${metrics_file}" ]]; then
        log_error "Metrics file not found: ${metrics_file}"
        return 1
    fi

    log_info "Submitting usage report to GCP Service Control API..."

    local token=$(get_access_token)
    local service_name="marketplace.googleapis.com"
    local operation_id=$(uuidgen)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Read metrics
    local metrics_data=$(cat "${metrics_file}")

    # Build Service Control API request
    local request_body=$(cat <<EOF
{
  "serviceName": "${service_name}",
  "operations": [
    {
      "operationId": "${operation_id}",
      "operationName": "usage_report",
      "consumerId": "project:${GCP_PROJECT_ID}",
      "startTime": "${timestamp}",
      "endTime": "${timestamp}",
      "labels": {
        "servicecontrol.googleapis.com/service_agent": "marketplace-metering"
      },
      "metricValueSets": [
        {
          "metricName": "usage_metrics",
          "metricValues": [
            {
              "labels": {},
              "int64Value": "1"
            }
          ]
        }
      ]
    }
  ]
}
EOF
)

    # Submit to API
    local response=$(curl -s -w "\n%{http_code}" -X POST \
        "${METERING_API_ENDPOINT}/services/${service_name}:report" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "${request_body}")

    local http_code=$(echo "${response}" | tail -n1)
    local body=$(echo "${response}" | head -n-1)

    if [[ "${http_code}" == "200" ]]; then
        log_success "Usage report submitted successfully"
        return 0
    else
        log_error "Failed to submit usage report. HTTP ${http_code}: ${body}"
        return 1
    fi
}

# Query billing data
query_billing_data() {
    local start_date=$1
    local end_date=$2

    log_info "Querying billing data from ${start_date} to ${end_date}..."

    local token=$(get_access_token)

    # Query BigQuery for billing data
    local query="
        SELECT
            DATE(usage_start_time) as usage_date,
            service.description as service,
            SUM(cost) as total_cost,
            SUM(usage.amount) as usage_amount,
            usage.unit as usage_unit
        FROM \`${GCP_PROJECT_ID}.billing_export.gcp_billing_export_*\`
        WHERE DATE(usage_start_time) BETWEEN '${start_date}' AND '${end_date}'
        GROUP BY usage_date, service, usage_unit
        ORDER BY usage_date DESC, total_cost DESC
    "

    local output_file="${DATA_DIR}/billing_query_$(date +%s).json"

    bq query --project_id="${GCP_PROJECT_ID}" \
        --format=json \
        --use_legacy_sql=false \
        "${query}" > "${output_file}" 2>/dev/null || true

    if [[ -f "${output_file}" ]]; then
        log_success "Billing data saved to: ${output_file}"
        echo "${output_file}"
    else
        log_error "Failed to query billing data"
        return 1
    fi
}

# Update budget alerts
update_budget_alerts() {
    local budget_name=$1
    local amount=$2

    log_info "Updating budget alert: ${budget_name} = ${amount}"

    local token=$(get_access_token)

    # Create or update budget
    local budget_json=$(cat <<EOF
{
  "displayName": "${budget_name}",
  "budgetFilter": {
    "projects": ["projects/${GCP_PROJECT_ID}"]
  },
  "amount": {
    "specifiedAmount": {
      "currencyCode": "USD",
      "units": "${amount}"
    }
  },
  "thresholdRules": [
    {
      "thresholdPercent": 0.5,
      "spendBasis": "CURRENT_SPEND"
    },
    {
      "thresholdPercent": 0.9,
      "spendBasis": "CURRENT_SPEND"
    },
    {
      "thresholdPercent": 1.0,
      "spendBasis": "CURRENT_SPEND"
    }
  ]
}
EOF
)

    local response=$(curl -s -w "\n%{http_code}" -X POST \
        "${BILLING_API_ENDPOINT}/billingAccounts/${GCP_BILLING_ACCOUNT_ID}/budgets" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "${budget_json}")

    local http_code=$(echo "${response}" | tail -n1)

    if [[ "${http_code}" == "200" ]]; then
        log_success "Budget alert updated successfully"
    else
        log_error "Failed to update budget alert. HTTP ${http_code}"
    fi
}

################################################################################
# Cost Allocation
################################################################################

# Apply cost allocation labels
apply_cost_labels() {
    local resource_type=$1
    local resource_name=$2
    shift 2
    local labels=("$@")

    log_info "Applying cost labels to ${resource_type}/${resource_name}..."

    case "${resource_type}" in
        "instance")
            for label in "${labels[@]}"; do
                local key=$(echo "${label}" | cut -d= -f1)
                local value=$(echo "${label}" | cut -d= -f2)
                gcloud compute instances add-labels "${resource_name}" \
                    --labels="${key}=${value}" \
                    --project="${GCP_PROJECT_ID}" \
                    --zone="${GCP_REGION}-a" 2>/dev/null || true
            done
            ;;
        "bucket")
            # Apply labels to Cloud Storage bucket
            for label in "${labels[@]}"; do
                gsutil label ch -l "${label}" "gs://${resource_name}" 2>/dev/null || true
            done
            ;;
        "disk")
            for label in "${labels[@]}"; do
                local key=$(echo "${label}" | cut -d= -f1)
                local value=$(echo "${label}" | cut -d= -f2)
                gcloud compute disks add-labels "${resource_name}" \
                    --labels="${key}=${value}" \
                    --project="${GCP_PROJECT_ID}" \
                    --zone="${GCP_REGION}-a" 2>/dev/null || true
            done
            ;;
    esac

    log_success "Cost labels applied"
}

# Generate cost allocation report
generate_cost_allocation_report() {
    local period=$1  # daily, weekly, monthly

    log_info "Generating cost allocation report for period: ${period}..."

    local output_file="${DATA_DIR}/cost_allocation_${period}_$(date +%s).csv"

    # Query billing data grouped by labels
    local query="
        SELECT
            labels.key as label_key,
            labels.value as label_value,
            service.description as service,
            SUM(cost) as total_cost,
            COUNT(*) as usage_count
        FROM \`${GCP_PROJECT_ID}.billing_export.gcp_billing_export_*\`,
        UNNEST(labels) as labels
        WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 ${period})
        GROUP BY label_key, label_value, service
        ORDER BY total_cost DESC
    "

    bq query --project_id="${GCP_PROJECT_ID}" \
        --format=csv \
        --use_legacy_sql=false \
        "${query}" > "${output_file}" 2>/dev/null || true

    if [[ -f "${output_file}" ]]; then
        log_success "Cost allocation report generated: ${output_file}"
        echo "${output_file}"
    else
        log_error "Failed to generate cost allocation report"
        return 1
    fi
}

# Calculate cost by team/project
calculate_cost_by_dimension() {
    local dimension=$1  # team, project, environment, etc.

    log_info "Calculating costs by ${dimension}..."

    local output_file="${DATA_DIR}/cost_by_${dimension}_$(date +%s).json"

    local query="
        SELECT
            labels.value as ${dimension},
            SUM(cost) as total_cost,
            SUM(usage.amount) as total_usage
        FROM \`${GCP_PROJECT_ID}.billing_export.gcp_billing_export_*\`,
        UNNEST(labels) as labels
        WHERE labels.key = '${dimension}'
            AND DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        GROUP BY ${dimension}
        ORDER BY total_cost DESC
    "

    bq query --project_id="${GCP_PROJECT_ID}" \
        --format=json \
        --use_legacy_sql=false \
        "${query}" > "${output_file}" 2>/dev/null || true

    if [[ -f "${output_file}" ]]; then
        log_success "Cost calculation complete: ${output_file}"
        cat "${output_file}" | jq '.'
    else
        log_error "Failed to calculate costs"
        return 1
    fi
}

################################################################################
# Reporting
################################################################################

# Generate usage summary
generate_usage_summary() {
    log_info "Generating usage summary..."

    local summary_file="${DATA_DIR}/usage_summary_$(date +%Y%m%d).txt"

    cat > "${summary_file}" <<EOF
================================================================================
GCP MARKETPLACE USAGE SUMMARY
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
================================================================================

Project: ${GCP_PROJECT_ID}
Region: ${GCP_REGION}

COMPUTE METRICS
---------------
$(collect_compute_metrics | jq -r '.metrics | to_entries | .[] | "\(.key): \(.value)"')

STORAGE METRICS
---------------
$(collect_storage_metrics | jq -r '.metrics | to_entries | .[] | "\(.key): \(.value)"')

API METRICS
-----------
$(collect_api_metrics | jq -r '.metrics | to_entries | .[] | "\(.key): \(.value)"')

NETWORK METRICS
---------------
$(collect_network_metrics | jq -r '.metrics | to_entries | .[] | "\(.key): \(.value)"')

USER METRICS
------------
$(collect_user_metrics | jq -r '.metrics | to_entries | .[] | "\(.key): \(.value)"')

================================================================================
EOF

    cat "${summary_file}"
    log_success "Usage summary saved to: ${summary_file}"
}

# Send report via email
send_email_report() {
    local report_file=$1
    local recipient=$2
    local subject=$3

    log_info "Sending email report to ${recipient}..."

    if command -v sendmail >/dev/null 2>&1; then
        (
            echo "To: ${recipient}"
            echo "Subject: ${subject}"
            echo "Content-Type: text/plain"
            echo ""
            cat "${report_file}"
        ) | sendmail -t

        log_success "Email report sent"
    else
        log_warn "sendmail not available, skipping email"
    fi
}

################################################################################
# Monitoring & Alerting
################################################################################

# Check budget status
check_budget_status() {
    log_info "Checking budget status..."

    local token=$(get_access_token)

    # List all budgets
    local budgets=$(curl -s -X GET \
        "${BILLING_API_ENDPOINT}/billingAccounts/${GCP_BILLING_ACCOUNT_ID}/budgets" \
        -H "Authorization: Bearer ${token}")

    echo "${budgets}" | jq -r '.budgets[] |
        "Budget: \(.displayName) | Amount: \(.amount.specifiedAmount.units) USD | Current Spend: \(.budgetAmounts.currentSpend.units // 0) USD"'
}

# Check quota usage
check_quota_usage() {
    log_info "Checking quota usage..."

    local quotas=$(gcloud compute project-info describe \
        --project="${GCP_PROJECT_ID}" \
        --format=json | jq -r '.quotas[] |
        "\(.metric): \(.usage)/\(.limit) (\(.usage / .limit * 100 | floor)%)"')

    echo "${quotas}"
}

# Send alert
send_alert() {
    local severity=$1
    local message=$2

    log_warn "ALERT [${severity}]: ${message}"

    # Send to Slack if webhook configured
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -d @- <<EOF
{
  "text": ":warning: *${severity}*: ${message}",
  "username": "GCP Billing Monitor"
}
EOF
    fi

    # Send to PubSub if enabled
    if [[ -n "${PUBSUB_ALERT_TOPIC:-}" ]]; then
        gcloud pubsub topics publish "${PUBSUB_ALERT_TOPIC}" \
            --message="${message}" \
            --attribute="severity=${severity}" \
            --project="${GCP_PROJECT_ID}" 2>/dev/null || true
    fi
}

################################################################################
# Background Service
################################################################################

# Run metering service continuously
run_metering_service() {
    log_info "Starting metering service (interval: ${REPORTING_INTERVAL}s)..."

    while true; do
        local cycle_start=$(date +%s)

        # Collect metrics
        local metrics_file=$(collect_all_metrics)

        # Submit to GCP
        if ! submit_usage_report "${metrics_file}"; then
            log_error "Failed to submit usage report, will retry next cycle"
        fi

        # Check budgets and quotas
        check_budget_status
        check_quota_usage

        local cycle_end=$(date +%s)
        local cycle_duration=$((cycle_end - cycle_start))
        local sleep_time=$((REPORTING_INTERVAL - cycle_duration))

        if [[ ${sleep_time} -gt 0 ]]; then
            log_info "Cycle complete in ${cycle_duration}s, sleeping for ${sleep_time}s..."
            sleep "${sleep_time}"
        else
            log_warn "Cycle took longer than interval (${cycle_duration}s > ${REPORTING_INTERVAL}s)"
        fi
    done
}

################################################################################
# Command Handlers
################################################################################

cmd_collect() {
    collect_all_metrics
}

cmd_report() {
    generate_usage_summary
}

cmd_submit() {
    local metrics_file=${1:-$(collect_all_metrics)}
    submit_usage_report "${metrics_file}"
}

cmd_query() {
    local start_date=${1:-$(date -d '7 days ago' +%Y-%m-%d)}
    local end_date=${2:-$(date +%Y-%m-%d)}
    query_billing_data "${start_date}" "${end_date}"
}

cmd_allocate() {
    local period=${1:-daily}
    generate_cost_allocation_report "${period}"
}

cmd_budget() {
    check_budget_status
}

cmd_quota() {
    check_quota_usage
}

cmd_service() {
    run_metering_service
}

cmd_label() {
    local resource_type=$1
    local resource_name=$2
    shift 2
    apply_cost_labels "${resource_type}" "${resource_name}" "$@"
}

cmd_calculate() {
    local dimension=${1:-team}
    calculate_cost_by_dimension "${dimension}"
}

################################################################################
# Main
################################################################################

usage() {
    cat <<EOF
Usage: $0 [command] [options]

Commands:
  collect               Collect all usage metrics
  report                Generate usage summary report
  submit [file]         Submit usage report to GCP API
  query [start] [end]   Query billing data for date range
  allocate [period]     Generate cost allocation report (daily/weekly/monthly)
  budget                Check budget status
  quota                 Check quota usage
  service               Run continuous metering service
  label <type> <name>   Apply cost allocation labels to resource
  calculate [dim]       Calculate costs by dimension (team/project/env)

Examples:
  $0 collect
  $0 report
  $0 submit /path/to/metrics.json
  $0 query 2026-01-01 2026-01-31
  $0 allocate monthly
  $0 label instance my-vm environment=prod team=engineering
  $0 calculate team

Environment Variables:
  GCP_PROJECT_ID              GCP project ID
  GCP_BILLING_ACCOUNT_ID      GCP billing account ID
  GCP_SERVICE_ACCOUNT_KEY_PATH Path to service account key file
  GCP_REGION                  GCP region (default: us-central1)
  REPORTING_INTERVAL          Reporting interval in seconds (default: 3600)
  SLACK_WEBHOOK_URL           Slack webhook URL for alerts
  PUBSUB_ALERT_TOPIC          PubSub topic for alerts

EOF
    exit 1
}

main() {
    init_dirs
    check_prerequisites

    local command=${1:-}
    shift || true

    case "${command}" in
        collect)    cmd_collect "$@" ;;
        report)     cmd_report "$@" ;;
        submit)     cmd_submit "$@" ;;
        query)      cmd_query "$@" ;;
        allocate)   cmd_allocate "$@" ;;
        budget)     cmd_budget "$@" ;;
        quota)      cmd_quota "$@" ;;
        service)    cmd_service "$@" ;;
        label)      cmd_label "$@" ;;
        calculate)  cmd_calculate "$@" ;;
        *)          usage ;;
    esac
}

# Only run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
