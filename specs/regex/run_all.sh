#!/usr/bin/env bash
# =============================================================================
# run_all.sh — Regex test suite runner
# 
# Runs all 5 regex test suites through the Lou interpreter and reports results.
# Exit code: 0 if all tests pass, 1 if any fail.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOU_BIN="${LOU_BIN:-$(cd "$SCRIPT_DIR/../../../../.." && pwd)/zig-out/bin/lou}"

if [ ! -x "$LOU_BIN" ]; then
    echo "ERROR: Lou binary not found at $LOU_BIN"
    echo "Build it first: zig build"
    echo "Or set LOU_BIN env var to the lou executable path"
    exit 1
fi

echo "============================================"
echo "  Regex Test Suite Runner"
echo "  Lou: $LOU_BIN"
echo "============================================"
echo ""

TOTAL=0
PASSED=0
FAILED=0
FAILED_SUITES=""
FULL_LOG=$(mktemp)
trap "if [ \"$FAILED\" -eq 0 ]; then rm -f \"$FULL_LOG\"; else echo \"  Full output saved to: $FULL_LOG\"; fi" EXIT

run_suite() {
    local name="$1"
    local file="$2"

    echo "  Running: $name ($file)"

    # Run the test and capture output
    set +e
    output=$("$LOU_BIN" run "$SCRIPT_DIR/$file" 2>&1)
    exit_code=$?
    set -e

    # Extract summary info
    total_line=$(echo "$output" | grep -i "TOTAL:" | tail -1)
    pass_line=$(echo "$output" | grep -i "PASS:" | tail -1)
    fail_line=$(echo "$output" | grep -i "FAIL:" | tail -1)

    total_num=$(echo "$total_line" | grep -oE '[0-9]+' | tail -1)
    pass_num=$(echo "$pass_line" | grep -oE '[0-9]+' | tail -1)
    fail_num=$(echo "$fail_line" | grep -oE '[0-9]+' | tail -1)

    # Fallback: count from exit code
    if [ -z "$fail_num" ] || [ "$fail_num" = "" ]; then
        fail_num=0
    fi

    if [ "$exit_code" -eq 0 ] && { [ -z "$fail_num" ] || [ "$fail_num" -eq 0 ]; }; then
        if [ -n "$total_num" ]; then
            echo "    ✓ $pass_num/$total_num passed"
        else
            echo "    ✓ PASSED"
        fi
        PASSED=$((PASSED + 1))
    else
        echo "    ✗ FAILED (exit=$exit_code, fails=$fail_num)"
        FAILED=$((FAILED + 1))
        FAILED_SUITES="$FAILED_SUITES $name"
        # Show failures
        echo "$output" | grep -i "FAIL" | head -20
    fi
    TOTAL=$((TOTAL + 1))

    # Log full output
    echo "=== $name ===" >> "$FULL_LOG"
    echo "$output" >> "$FULL_LOG"
    echo "" >> "$FULL_LOG"
}

run_suite "01-basic"          "01-basic.js"
run_suite "02-advanced"       "02-advanced.js"
run_suite "03-exec-basic"     "03-exec-basic.js"
run_suite "04-exec-named"     "04-exec-named-groups.js"
run_suite "05-exec-edge"      "05-exec-edge.js"

echo ""
echo "============================================"
echo "  Results: $PASSED/$TOTAL suites passed"

if [ "$FAILED" -eq 0 ]; then
    echo "  ALL REGEX TESTS PASSED"
    exit 0
else
    echo "  Failed:$FAILED_SUITES"
    echo ""
    exit 1
fi
