#!/bin/bash
# ============================================================================
# forensics-vol3.sh — volatility3 Docker wrapper.
#
# Usage:  bash forensics-vol3.sh CASE_ID PLUGIN [plugin_args...]
#
# What it does:
#   Runs a volatility3 plugin against the first .mem file in the case's
#   evidence directory. Saves output to case/raw/vol3_PLUGIN.csv (or .txt/.json).
#   No need to remember the 200-character docker command.
#
# Examples:
#   bash forensics-vol3.sh INC-2026-0624-0001 windows.pslist.PsList
#   bash forensics-vol3.sh INC-2026-0624-0001 windows.netscan.NetScan
#   bash forensics-vol3.sh INC-2026-0624-0001 windows.malfind.Malfind
#   bash forensics-vol3.sh INC-2026-0624-0001 windows.filescan.FileScan
#   bash forensics-vol3.sh INC-2026-0624-0001 windows.dumpfiles --virtaddr 0xe6892af1f1f0
#   bash forensics-vol3.sh INC-2026-0624-0001 windows.cmdline.CmdLine --pid 9920
#
# Output: case/raw/vol3_windows.pslist.PsList.csv (auto-determined extension)
# ============================================================================
set -uo pipefail

CASE_ID="${1:?Usage: forensics-vol3.sh CASE_ID PLUGIN [args...]}"
PLUGIN="${2:?Usage: forensics-vol3.sh CASE_ID PLUGIN [args...]}"
shift 2
PLUGIN_ARGS="$@"

FORENSICS_DIR="/home/niel/forensics"
CASE_DIR="$FORENSICS_DIR/cases/$CASE_ID"
EVIDENCE_DIR="$CASE_DIR/evidence"
RAW_DIR="$CASE_DIR/raw"

if [ ! -d "$CASE_DIR" ]; then
    echo "ERROR: Case directory not found: $CASE_DIR" >&2
    exit 1
fi

# Find the memory dump
MEM_FILE=$(ls "$EVIDENCE_DIR"/*.mem "$EVIDENCE_DIR"/*.dmp "$EVIDENCE_DIR"/*.raw "$EVIDENCE_DIR"/*.vmem 2>/dev/null | head -1)
if [ -z "$MEM_FILE" ]; then
    echo "ERROR: No memory dump (.mem/.dmp/.raw/.vmem) found in $EVIDENCE_DIR" >&2
    echo "Register evidence first: bash forensics-register.sh $CASE_ID /path/to/dump.mem" >&2
    exit 1
fi

# Determine output file and extension
# .json for malfind, .csv for most others, .txt as fallback
SAFE_NAME=$(echo "$PLUGIN" | tr '/' '_' | tr '.' '_')
case "$PLUGIN" in
    *.Malfind|*.VadInfo|*.VadWalk)  EXT="json" ;;
    *)                               EXT="csv" ;;
esac
OUTPUT="$RAW_DIR/vol3_${SAFE_NAME}.${EXT}"

echo "=== Volatility3 ==="
echo "  Case:   $CASE_ID"
echo "  Plugin: $PLUGIN"
echo "  Dump:   $(basename "$MEM_FILE")"
echo "  Output: $(basename "$OUTPUT")"
echo ""

mkdir -p "$RAW_DIR"

docker run --rm \
    -v "$EVIDENCE_DIR:/evidence:ro" \
    -v "$RAW_DIR:/output" \
    forensics-volatility3:2.7.0 \
    -f "/evidence/$(basename "$MEM_FILE")" \
    "$PLUGIN" $PLUGIN_ARGS 2>/dev/null | tee "$OUTPUT"

LINE_COUNT=$(wc -l < "$OUTPUT" 2>/dev/null || echo 0)
echo ""
echo "  → Saved: $OUTPUT ($(du -h "$OUTPUT" | cut -f1), ${LINE_COUNT} lines)"
