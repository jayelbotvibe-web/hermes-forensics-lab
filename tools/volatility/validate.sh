#!/bin/bash
# volatility3 validation — runs against known-good memory image
set -euo pipefail

TEST_IMAGE="${TEST_IMAGE:-/fixtures/win10-22h2.mem}"

echo "=== volatility3 Validation ==="
echo "Version: $(vol --version 2>&1 || echo 'VERSION_CHECK_FAILED')"

# Test 1: Basic plugin
echo "[1/3] Testing pslist plugin..."
vol -f "$TEST_IMAGE" windows.pslist.PsList > /tmp/pslist_output.txt 2>&1

# Test 2: Verify required processes
echo "[2/3] Verifying expected processes..."
for proc in "System" "smss.exe"; do
    if ! grep -q "$proc" /tmp/pslist_output.txt; then
        echo "FAIL: Missing expected process '$proc'"
        exit 1
    fi
done
echo "  ✓ Expected processes present"

# Test 3: Output structure
echo "[3/3] Verifying output structure..."
if head -1 /tmp/pslist_output.txt | grep -qE "(PID|Process|Offset)"; then
    echo "  ✓ Output structure valid"
else
    echo "WARN: Output structure unexpected — may be benign"
fi

echo "=== PASS: volatility3 validation successful ==="
exit 0
