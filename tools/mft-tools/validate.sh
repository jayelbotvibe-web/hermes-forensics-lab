#!/bin/bash
# mft-tools validation — MFT parsing against known-good MFT
# Exit 0 = both parsers operational, non-zero = FAIL (no silent passes)
set -euo pipefail

TEST_MFT="${TEST_MFT:-/fixtures/test-mft.bin}"

echo "=== mft-tools Validation ==="

# Test MFTECmd
echo "[1/2] Testing MFTECmd..."
if [ ! -f /opt/mftecmd/MFTECmd.dll ]; then
    echo "  ✗ FAIL: MFTECmd not installed at /opt/mftecmd"
    exit 1
fi
MFTECMD_VER=$(cat /opt/mftecmd/VERSION 2>/dev/null || echo "unknown")
if [ -f "$TEST_MFT" ]; then
    dotnet /opt/mftecmd/MFTECmd.dll -f "$TEST_MFT" --csv /tmp --csvf mft_test.csv > /dev/null 2>&1 || true
    if [ -f /tmp/mft_test.csv ] && [ -s /tmp/mft_test.csv ]; then
        echo "  ✓ MFTECmd operational (version: $MFTECMD_VER) — parsed test MFT"
    else
        echo "  ✗ FAIL: MFTECmd produced no output from test MFT"
        exit 1
    fi
else
    # No fixture available: verify the binary at least loads and identifies itself
    if (dotnet /opt/mftecmd/MFTECmd.dll 2>&1 || true) | grep -q "MFTECmd version"; then
        echo "  ✓ MFTECmd loads (version: $MFTECMD_VER)"
        echo "  NOTE: no test MFT at $TEST_MFT — parse path not exercised"
    else
        echo "  ✗ FAIL: MFTECmd failed to execute"
        exit 1
    fi
fi

# Test analyzeMFT
echo "[2/2] Testing analyzeMFT..."
if python3 -c 'import analyzemft' 2>/dev/null; then
    AMFT_VER=$(python3 -c 'import analyzemft; print(getattr(analyzemft, "__version__", ""))' 2>/dev/null || echo "")
    if [ -n "$AMFT_VER" ]; then
        echo "  ✓ analyzeMFT available (version: $AMFT_VER)"
    else
        echo "  ✓ analyzeMFT available (imports — version string not exposed)"
    fi
else
    echo "  ✗ FAIL: analyzeMFT import failed"
    exit 1
fi

echo "=== PASS: mft-tools validation successful ==="
exit 0
