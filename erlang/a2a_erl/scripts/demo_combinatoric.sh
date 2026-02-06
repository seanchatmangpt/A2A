#!/bin/bash
# Y Combinator Demo - YAWL Combinatoric Testing Demo Runner
#
# Quick start: ./scripts/demo_combinatoric.sh quick
# Full demo:   ./scripts/demo_combinatoric.sh full

set -e

DEMO_TYPE="${1:-quick}"
REBAR3=${REBAR3:-rebar3}
ERL=${ERL:-erl}

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Y Combinator Demo - YAWL Combinatoric Testing           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Change to project directory
cd "$(dirname "$0")/.."

echo "📦 Compiling..."
$REBAR3 compile 2>&1 | grep -v "==>" || true

echo ""
echo "🚀 Starting demo: $DEMO_TYPE"
echo "─────────────────────────────────────────────────────────"
echo ""

# Create temporary Erlang script for demo
cat > /tmp/y_combinator_demo.erl << 'ERLEOF'
#!/usr/bin/env escript
main([Arg]) ->
    DemoType = case Arg of
        "quick" -> quick;
        "medium" -> medium;
        "full" -> full;
        _ -> quick
    end,

    io:format("Starting Y Combinator Demo...~n~n"),

    %% Start application
    case application:ensure_all_started(a2a_erl) of
        {ok, _} -> io:format("[OK] Application started~n~n");
        {error, Reason} -> io:format("[ERROR] Failed to start: ~p~n", [Reason]), halt(1)
    end,

    %% Run demo based on type
    Result = case DemoType of
        quick ->
            io:format("Running Quick Demo (30 seconds)~n"),
            io:format("Patterns: basic_sequential, parallel_split~n~n"),
            y_combinator_demo:quick_demo();
        medium ->
            io:format("Running Medium Demo (2 minutes)~n"),
            io:format("Patterns: 5 core patterns~n~n"),
            y_combinator_demo:medium_demo();
        full ->
            io:format("Running Full Demo (all patterns)~n"),
            io:format("Patterns: All 43 YAWL patterns~n~n"),
            y_combinator_demo:full_demo()
    end,

    io:format("~nDemo result: ~p~n", [Result]),
    y_combinator_demo:stop(),
    io:format("~n✓ Demo completed.~n"),
    halt(0).
ERLEOF

# Run the demo
$ERL -pa _build/default/lib/a2a_erl/ebin -noshell \
     -eval "application:ensure_all_started(a2a_erl), y_combinator_demo:${DEMO_TYPE}(), init:stop()."

echo ""
echo "─────────────────────────────────────────────────────────"
echo "✓ Demo complete!"
echo ""
echo "For interactive mode, run:"
echo "  rebar3 shell --eval 'y_combinator_demo:interactive()'"
