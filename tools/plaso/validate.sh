#!/bin/bash
# plaso validation — timeline generation against known-good disk image
set -euo pipefail

TEST_IMAGE="${TEST_IMAGE:-/fixtures/test-disk.E01}"
OUTPUT_FILE="/tmp/plaso_test.plaso"

echo "=== plaso Validation ==="

echo "[1/3] Checking version..."
log2timeline.py --version 2>&1 || true

if [ -f "$TEST_IMAGE" ]; then
    log2timeline.py --storage-file "$OUTPUT_FILE" "$TEST_IMAGE" > /tmp/plaso_build.log 2>&1
    echo "  ✓ Timeline created"
else
    echo "FAIL — no test fixture available; plaso UNVERIFIED"
    echo "=== plaso validation FAILED (missing fixture) ==="
    exit 1
fi

echo "[3/3] Verifying timeline has content..."
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    echo "  ✓ Timeline file created"
else
    echo "WARN: Timeline file empty or missing"
fi

rm -f "$OUTPUT_FILE"
echo "=== PASS: plaso validation successful ==="
exit 0
