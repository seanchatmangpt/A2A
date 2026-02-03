#!/bin/bash

# Dual Build System Test Script
# Tests both rebar3 and erlang.mk integration with HotCI

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "🧪 Testing Dual Build System (rebar3 + erlang.mk) + HotCI"
echo "======================================================"
echo ""

# Check tools availability
echo -e "${BLUE}📋 Checking Tool Availability:${NC}"
echo ""

REBAR3_AVAILABLE=$(command -v rebar3 2>/dev/null && echo "✅ Available" || echo "❌ Not available")
ERLANG_MK_AVAILABLE=$(command -v erlang.mk 2>/dev/null && echo "✅ Available" || echo "❌ Not available")
DOCKER_AVAILABLE=$(command -v docker 2>/dev/null && echo "✅ Available" || echo "❌ Not available")

echo "  rebar3: $REBAR3_AVAILABLE"
echo "  erlang.mk: $ERLANG_MK_AVAILABLE"
echo "  Docker: $DOCKER_AVAILABLE"

# Check if HotCI is available
if [ -d "hotci" ]; then
    echo "  HotCI: ✅ Available"
else
    echo "  HotCI: ❌ Not available"
fi

echo ""

# Check rebar3 dependencies
echo -e "${BLUE}📦 Checking Dependencies:${NC}"
if [ -f "rebar.config" ]; then
    echo "  rebar.config: ✅ Found"
    if [ "$REBAR3_AVAILABLE" = "✅ Available" ]; then
        echo -n "  Testing rebar3: "
        rebar3 version > /dev/null 2>&1 && echo "✅ Working" || echo "❌ Failed"
    else
        echo "  rebar3: ❌ Not available for testing"
    fi
else
    echo "  rebar.config: ❌ Not found"
fi

echo ""

# Test rebar3 build
echo -e "${BLUE}🔨 Testing rebar3 Build:${NC}"
if [ "$REBAR3_AVAILABLE" = "✅ Available" ] && [ -f "rebar.config" ]; then
    echo -n "  Compiling: "
    if rebar3 compile > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Success${NC}"
        echo "  Modules built: $(find _build/default/lib/*/ebin -name "*.beam" 2>/dev/null | wc -l)"
    else
        echo -e "${RED}❌ Failed${NC}"
    fi

    echo -n "  Running tests: "
    if rebar3 eunit > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Success${NC}"
    else
        echo -e "${RED}❌ Failed${NC}"
    fi
else
    echo "  rebar3 build skipped (missing dependencies)"
fi

echo ""

# Test erlang.mk if available
echo -e "${BLUE}🔨 Testing erlang.mk Build:${NC}"
if [ "$ERLANG_MK_AVAILABLE" = "✅ Available" ]; then
    echo -n "  Testing erlang.mk: "
    if erlang.mk -h > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Working${NC}"

        # Test build with erlang.mk
        echo -n "  Building: "
        if make -f Makefile.erlang.mk rebar3_build > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Success${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi
    else
        echo -e "${RED}❌ Failed${NC}"
    fi
else
    echo "  erlang.mk: ❌ Not available"
    echo "  🔄 Would you like to install erlang.mk?"
    echo "     make init_erlangmk"
fi

echo ""

# Test HotCI features
echo -e "${BLUE}🔥 Testing HotCI Features:${NC}"
if [ -d "hotci" ]; then
    echo "  HotCI directory: ✅ Found"

    # Test HotCI build with rebar3
    if [ "$REBAR3_AVAILABLE" = "✅ Available" ]; then
        echo -n "  HotCI build: "
        if rebar3 as hotci compile > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Success${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi
    fi

    # Test HotCI tests
    if [ "$REBAR3_AVAILABLE" = "✅ Available" ]; then
        echo -n "  HotCI tests: "
        if rebar3 as hotci ct > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Success${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi
    fi
else
    echo "  HotCI: ❌ Not available"
    echo "  🔄 Run 'make hotci_setup' to set up HotCI"
fi

echo ""

# Test dual build system
echo -e "${BLUE}🔄 Testing Dual Build System:${NC}"
if [ "$REBAR3_AVAILABLE" = "✅ Available" ]; then
    echo -n "  Dual build: "
    if make dual_build > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Success${NC}"
    else
        echo -e "${RED}❌ Failed${NC}"
    fi
else
    echo "  Dual build: ❌ rebar3 not available"
fi

echo ""

# Show status summary
echo -e "${BLUE}📊 Status Summary:${NC}"
echo ""

# Check if both build systems work
BOTH_SYSTEMS="❌ Not fully functional"
if [ "$REBAR3_AVAILABLE" = "✅ Available" ] && [ "$ERLANG_MK_AVAILABLE" = "✅ Available" ]; then
    BOTH_SYSTEMS="✅ Both functional"
elif [ "$REBAR3_AVAILABLE" = "✅ Available" ]; then
    BOTH_SYSTEMS="⚠️  rebar3 only"
fi

echo "  Build Systems: $BOTH_SYSTEMS"

# HotCI status
HOTCI_STATUS="❌ Not functional"
if [ -d "hotci" ] && [ "$REBAR3_AVAILABLE" = "✅ Available" ]; then
    HOTCI_STATUS="✅ Functional"
elif [ -d "hotci" ]; then
    HOTCI_STATUS="⚠️  Needs rebar3"
fi
echo "  HotCI: $HOTCI_STATUS"

# Development readiness
DEV_READY="❌ Not ready"
if [ "$REBAR3_AVAILABLE" = "✅ Available" ] && [ -f "rebar.config" ]; then
    DEV_READY="✅ Ready"
fi
echo "  Development Ready: $DEV_READY"

echo ""

# Next steps
echo -e "${YELLOW}🚀 Next Steps:${NC}"
if [ "$ERLANG_MK_AVAILABLE" = "❌ Not available" ]; then
    echo "  1. Install erlang.mk: make init_erlangmk"
fi
if [ ! -d "hotci" ]; then
    echo "  2. Set up HotCI: make hotci_setup"
fi
if [ "$REBAR3_AVAILABLE" = "❌ Not available" ]; then
    echo "  3. Install rebar3: https://rebar3.org/"
fi
echo "  4. Start development: make dev"
echo "  5. Run tests: make test"
echo "  6. Build release: make release"

echo ""
echo -e "${GREEN}🎉 Dual Build System Test Complete!${NC}"