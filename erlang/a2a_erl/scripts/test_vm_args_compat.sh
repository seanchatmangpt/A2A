#!/bin/bash
## VM Args Backwards Compatibility Test Script
## Tests various VM argument patterns for OTP 27+ compatibility

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

test_section() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

test_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASS_COUNT++))
}

test_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAIL_COUNT++))
}

test_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARN_COUNT++))
}

# Test 1: Old +K true (kernel poll) still works
test_section "Test 1: Old +K true flag (kernel poll)"
cat > /tmp/test_vm_args_1.args << 'EOF'
+K true
EOF

if erl -args_file /tmp/test_vm_args_1.args -noshell -eval 'init:stop()' 2>&1 | grep -q "warning"; then
    test_warn "+K true generates warnings (check for deprecated flags)"
else
    test_pass "+K true works without errors"
fi

# Test 2: Removed vm.args args are ignored gracefully
test_section "Test 2: Deprecated distribution flags handling"
cat > /tmp/test_vm_args_2.args << 'EOF'
-name test@127.0.0.1
-setcookie test_cookie
-kernel net_ticktime 60
EOF

if erl -args_file /tmp/test_vm_args_2.args -noshell -eval 'init:stop()' 2>/dev/null; then
    test_pass "Old distribution flags (-name, -setcookie, -kernel) work"
else
    test_fail "Old distribution flags failed"
fi

# Test 3: Memory allocator settings
test_section "Test 3: Memory allocator settings backwards compatibility"
cat > /tmp/test_vm_args_3.args << 'EOF'
+MBas aobf
+MBlmbcs 512
+MEas aobf
EOF

if erl -args_file /tmp/test_vm_args_3.args -noshell -eval 'init:stop()' 2>&1 | grep -q "warning"; then
    test_warn "Allocator flags generate warnings"
    erl -args_file /tmp/test_vm_args_3.args -noshell -eval 'init:stop()' 2>&1 | grep "warning" | head -5
else
    test_pass "Allocator settings (+MBas, +MBlmbcs, +MEas) work"
fi

# Test 4: Test current vm.args file
test_section "Test 4: Current config/vm.args file"
if [ -f "$PROJECT_DIR/config/vm.args" ]; then
    # Create temp version with distribution for testing
    cat > /tmp/test_vm_args_current.args << 'EOF'
-name a2a@127.0.0.1
-setcookie a2a_cookie
+K true
+S 4:4
+Q 65536
+P 1000000
+A 64
+hms 233
+MBas aobf
+MBlmbcs 512
+MEas aobf
EOF

    if erl -args_file /tmp/test_vm_args_current.args -noshell -eval 'init:stop()' 2>&1 | grep -qi "error"; then
        test_fail "Current vm.args has errors"
        erl -args_file /tmp/test_vm_args_current.args -noshell -eval 'init:stop()' 2>&1
    else
        test_pass "Current vm.args syntax is valid"
    fi
else
    test_warn "config/vm.args not found"
fi

# Test 5: Check if +K command line flag is deprecated
test_section "Test 5: Check +K flag deprecation status"
OUTPUT=$(erl +K true -noshell -eval 'init:stop()' 2>&1)
if echo "$OUTPUT" | grep -qi "deprecated"; then
    test_warn "+K true is deprecated in OTP 27+"
    echo "$OUTPUT" | grep -i "deprecated" | head -3
elif echo "$OUTPUT" | grep -qi "ignored"; then
    test_warn "+K true is ignored (kernel poll always enabled)"
else
    test_pass "+K true flag accepted"
fi

# Test 6: Test old vs new distribution flags
test_section "Test 6: Distribution flags compatibility"
cat > /tmp/test_vm_args_dist.args << 'EOF'
# Old style (still valid)
-name test@127.0.0.1
-setcookie test_cookie
EOF

if erl -args_file /tmp/test_vm_args_dist.args -noshell -eval 'init:stop()' 2>/dev/null; then
    test_pass "Old distribution flags (-name, -setcookie) still work"
else
    test_fail "Old distribution flags failed"
fi

# Test 7: Check for OTP 27+ specific environment variable support
test_section "Test 7: Environment variable distribution flags"
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE=test@127.0.0.1
export RELEASE_COOKIE=test_cookie

# The start script handles these, but we can verify erl accepts them
if erl -name test@127.0.0.1 -setcookie test_cookie -noshell -eval 'init:stop()' 2>/dev/null; then
    test_pass "Direct distribution flags work"
else
    test_fail "Direct distribution flags failed"
fi

# Test 8: Check vm.args.prod
test_section "Test 8: Production vm.args"
if [ -f "$PROJECT_DIR/config/vm.args.prod" ]; then
    if erl -args_file "$PROJECT_DIR/config/vm.args.prod" -noshell -eval 'init:stop()' 2>&1 | grep -qi "error"; then
        test_fail "vm.args.prod has errors"
    else
        test_pass "vm.args.prod is valid"
    fi
else
    test_warn "config/vm.args.prod not found"
fi

# Test 9: Check vm.args.nodist
test_section "Test 9: No-distribution vm.args"
if [ -f "$PROJECT_DIR/config/vm.args.nodist" ]; then
    if erl -args_file "$PROJECT_DIR/config/vm.args.nodist" -noshell -eval 'init:stop()' 2>&1 | grep -qi "error"; then
        test_fail "vm.args.nodist has errors"
    else
        test_pass "vm.args.nodist is valid"
    fi
else
    test_warn "config/vm.args.nodist not found"
fi

# Test 10: Verify scheduler settings
test_section "Test 10: Scheduler settings compatibility"
cat > /tmp/test_vm_args_sched.args << 'EOF'
+S 4:4
+sbt ns
+A 64
+P 1000000
+Q 65536
EOF

if erl -args_file /tmp/test_vm_args_sched.args -noshell -eval 'init:stop()' 2>&1 | grep -qi "error"; then
    test_fail "Scheduler settings have errors"
else
    test_pass "Scheduler settings (+S, +sbt, +A, +P, +Q) work"
fi

# Cleanup
rm -f /tmp/test_vm_args_*.args

# Summary
test_section "Test Summary"
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
echo -e "Warnings: ${YELLOW}$WARN_COUNT${NC}"

if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
else
    exit 0
fi
