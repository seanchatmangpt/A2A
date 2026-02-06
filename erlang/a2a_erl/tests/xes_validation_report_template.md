# XES Validation Report Template

**IEEE 1849-2016 Compliance Report**

---

## Report Information

| Field | Value |
|-------|-------|
| Report ID | `{{REPORT_ID}}` |
| Generated | `{{TIMESTAMP}}` |
| Validator | YAWL XES Validator v1.0 |
| Standard | IEEE 1849-2016 (XES) |

---

## Executive Summary

| Metric | Value |
|--------|-------|
| Overall Status | `{{STATUS}}` |
| Tests Passed | `{{PASSED}}` / `{{TOTAL}}` |
| Tests Failed | `{{FAILED}}` / `{{TOTAL}}` |
| Warnings | `{{WARNINGS}}` |
| Compliance Level | `{{COMPLIANCE_LEVEL}}` |

---

## Compliance Categories

### 1. XML Well-Formedness

| Check | Status | Details |
|-------|--------|---------|
| XML Declaration | `{{XML_DECL_STATUS}}` | `{{XML_DECL_DETAILS}}` |
| Well-Formed XML | `{{WELLFORMED_STATUS}}` | `{{WELLFORMED_DETAILS}}` |
| Encoding (UTF-8) | `{{ENCODING_STATUS}}` | `{{ENCODING_DETAILS}}` |

**Notes:**
`{{XML_NOTES}}`

---

### 2. XES Structure Validation

| Check | Status | Details |
|-------|--------|---------|
| Log Element | `{{LOG_ELEMENT_STATUS}}` | `{{LOG_ELEMENT_DETAILS}}` |
| Trace Element(s) | `{{TRACE_ELEMENT_STATUS}}` | `{{TRACE_ELEMENT_DETAILS}}` |
| Event Element(s) | `{{EVENT_ELEMENT_STATUS}}` | `{{EVENT_ELEMENT_DETAILS}}` |
| Balanced Tags | `{{BALANCED_TAGS_STATUS}}` | `{{BALANCED_TAGS_DETAILS}}` |

**Notes:**
`{{STRUCTURE_NOTES}}`

---

### 3. Required Attributes

| Attribute | Status | Found | Notes |
|-----------|--------|-------|-------|
| `xes.version` | `{{XES_VERSION_STATUS}}` | `{{XES_VERSION_FOUND}}` | `{{XES_VERSION_VALUE}}` |
| `xmlns` | `{{XMLNS_STATUS}}` | `{{XMLNS_FOUND}}` | `{{XMLNS_VALUE}}` |
| `concept:name` | `{{CONCEPT_NAME_STATUS}}` | `{{CONCEPT_NAME_FOUND}}` | `{{CONCEPT_NAME_DETAILS}}` |
| `time:timestamp` | `{{TIMESTAMP_STATUS}}` | `{{TIMESTAMP_FOUND}}` | `{{TIMESTAMP_DETAILS}}` |

**Notes:**
`{{ATTRIBUTES_NOTES}}`

---

### 4. Extension Declarations

| Extension | Declared | URI | Status |
|-----------|----------|-----|--------|
| Time | `{{TIME_EXT_DECLARED}}` | `{{TIME_EXT_URI}}` | `{{TIME_EXT_STATUS}}` |
| Concept | `{{CONCEPT_EXT_DECLARED}}` | `{{CONCEPT_EXT_URI}}` | `{{CONCEPT_EXT_STATUS}}` |
| Lifecycle | `{{LIFECYCLE_EXT_DECLARED}}` | `{{LIFECYCLE_EXT_URI}}` | `{{LIFECYCLE_EXT_STATUS}}` |
| Organizational | `{{ORG_EXT_DECLARED}}` | `{{ORG_EXT_URI}}` | `{{ORG_EXT_STATUS}}` |
| Custom | `{{CUSTOM_EXT_DECLARED}}` | `{{CUSTOM_EXT_URI}}` | `{{CUSTOM_EXT_STATUS}}` |

**Notes:**
`{{EXTENSIONS_NOTES}}`

---

### 5. Timestamp Format Validation

| Check | Status | Details |
|-------|--------|---------|
| ISO 8601 Format | `{{ISO8601_STATUS}}` | `{{ISO8601_DETAILS}}` |
| Millisecond Precision | `{{MS_PRECISION_STATUS}}` | `{{MS_PRECISION_DETAILS}}` |
| UTC Timezone | `{{UTC_STATUS}}` | `{{UTC_DETAILS}}` |
| Timestamp Order | `{{ORDER_STATUS}}` | `{{ORDER_DETAILS}}` |

**Sample Timestamps Found:**
`{{TIMESTAMPS_SAMPLE}}`

**Notes:**
`{{TIMESTAMP_NOTES}}`

---

### 6. Attribute Type Validation

| Type | Count | Valid | Invalid |
|------|-------|-------|---------|
| `<string>` | `{{STRING_COUNT}}` | `{{STRING_VALID}}` | `{{STRING_INVALID}}` |
| `<date>` | `{{DATE_COUNT}}` | `{{DATE_VALID}}` | `{{DATE_INVALID}}` |
| `<int>` | `{{INT_COUNT}}` | `{{INT_VALID}}` | `{{INT_INVALID}}` |
| `<float>` | `{{FLOAT_COUNT}}` | `{{FLOAT_VALID}}` | `{{FLOAT_INVALID}}` |
| `<boolean>` | `{{BOOLEAN_COUNT}}` | `{{BOOLEAN_VALID}}` | `{{BOOLEAN_INVALID}}` |
| `<id>` | `{{ID_COUNT}}` | `{{ID_VALID}}` | `{{ID_INVALID}}` |
| `<list>` | `{{LIST_COUNT}}` | `{{LIST_VALID}}` | `{{LIST_INVALID}}` |

**Notes:**
`{{TYPES_NOTES}}`

---

### 7. Trace and Event Structure

| Metric | Value |
|--------|-------|
| Number of Traces | `{{NUM_TRACES}}` |
| Number of Events | `{{NUM_EVENTS}}` |
| Average Events per Trace | `{{AVG_EVENTS_PER_TRACE}}` |
| Min Events in Trace | `{{MIN_EVENTS}}` |
| Max Events in Trace | `{{MAX_EVENTS}}` |

**Trace Breakdown:**
`{{TRACE_BREAKDOWN}}`

**Notes:**
`{{TRACE_EVENT_NOTES}}`

---

### 8. Lifecycle Transition Validation

| Transition | Count | Valid Extensions |
|------------|-------|-----------------|
| `schedule` | `{{SCHEDULE_COUNT}}` | Standard |
| `assign` | `{{ASSIGN_COUNT}}` | Standard |
| `start` | `{{START_COUNT}}` | Standard |
| `suspend` | `{{SUSPEND_COUNT}}` | Standard |
| `resume` | `{{RESUME_COUNT}}` | Standard |
| `complete` | `{{COMPLETE_COUNT}}` | Standard |
| `withdraw` | `{{WITHDRAW_COUNT}}` | Standard |
| Custom | `{{CUSTOM_TRANS_COUNT}}` | `{{CUSTOM_TRANS_VALUES}}` |

**Notes:**
`{{LIFECYCLE_NOTES}}`

---

## Findings and Recommendations

### Critical Issues
`{{CRITICAL_ISSUES}}`

### Warnings
`{{WARNINGS_LIST}}`

### Recommendations
`{{RECOMMENDATIONS}}`

---

## Compliance Statement

Based on the validation tests performed, the XES file:

**`{{COMPLIANCE_STATEMENT}}`**

**Compliance Level: `{{COMPLIANCE_LEVEL}}`**

- `{{COMPLIANCE_DETAIL_1}}`
- `{{COMPLIANCE_DETAIL_2}}`
- `{{COMPLIANCE_DETAIL_3}}`

---

## Appendix A: Test Configuration

| Parameter | Value |
|-----------|-------|
| Validation Date | `{{VALIDATION_DATE}}` |
| XES File | `{{XES_FILE}}` |
| File Size | `{{FILE_SIZE}}` bytes |
| Schema Used | `{{SCHEMA_USED}}` |
| Strict Mode | `{{STRICT_MODE}}` |

---

## Appendix B: Validator Version

| Component | Version |
|-----------|---------|
| Validator | YAWL XES Validator v1.0 |
| XES Standard | IEEE 1849-2016 |
| XML Parser | xmerl (Erlang/OTP) |
| Test Framework | EUnit / Common Test |

---

## Report Sign-Off

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Validator | `{{VALIDATOR_NAME}}` | `{{VALIDATOR_SIGNATURE}}` | `{{SIGNOFF_DATE}}` |
| Reviewer | `{{REVIEWER_NAME}}` | `{{REVIEWER_SIGNATURE}}` | `{{REVIEWER_DATE}}` |

---

**End of Report**

---

## Template Usage Instructions

### Required Template Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `REPORT_ID` | Unique report identifier | `XES-VAL-2024-001` |
| `TIMESTAMP` | ISO 8601 timestamp | `2024-01-01T12:00:00Z` |
| `STATUS` | PASSED/FAILED/WARNINGS | `PASSED` |
| `PASSED` | Number of passed tests | `42` |
| `FAILED` | Number of failed tests | `0` |
| `TOTAL` | Total number of tests | `42` |
| `WARNINGS` | Number of warnings | `2` |
| `COMPLIANCE_LEVEL` | Compliance percentage | `100%` |

### Generating Reports

To generate a filled report:

```bash
escript xes_validation.escript workflow.xes --report validation_report.txt
```

Or use the template with your preferred templating engine to substitute the placeholder variables.
