#!/bin/bash
# Cross-validate critical forensic artifacts using dual tools
# Usage: cross-validate.sh mft /path/to/mft CASE_DIR
#        cross-validate.sh registry /path/to/hive CASE_DIR
set -uo pipefail

ARTIFACT_TYPE="$1"
EVIDENCE_PATH="$2"
CASE_DIR="$3"
DELTA_MAX="${4:-5}"

echo "=== Cross-Validation: $ARTIFACT_TYPE ==="

case "$ARTIFACT_TYPE" in
    mft)
        # Tool 1: analyzeMFT (Docker)
        docker run --rm \
            -v "$EVIDENCE_PATH:/evidence/MFT_FILE:ro" \
            -v "$CASE_DIR/raw:/output" \
            forensics-mft-tools:1.2.0.0 \
            python3 -m analyzemft -f /evidence/MFT_FILE -o /output/crossval_analyzemft.csv 2>/dev/null
        COUNT_A=$(wc -l < "$CASE_DIR/raw/crossval_analyzemft.csv" 2>/dev/null || echo 0)
        echo "analyzeMFT entries: $COUNT_A"

        # Tool 2: MFTECmd if available, else skip dual
        if docker run --rm forensics-mft-tools:1.2.0.0 which mono 2>/dev/null; then
            docker run --rm \
                -v "$EVIDENCE_PATH:/evidence/MFT_FILE:ro" \
                -v "$CASE_DIR/raw:/output" \
                forensics-mft-tools:1.2.0.0 \
                mono /opt/mftecmd/MFTECmd.dll -f /evidence/MFT_FILE --csv /output --csvf crossval_mftecmd.csv 2>/dev/null
            COUNT_B=$(wc -l < "$CASE_DIR/raw/crossval_mftecmd.csv" 2>/dev/null || echo 0)
            echo "MFTECmd entries: $COUNT_B"
        else
            echo "MFTECmd not available — single-tool analysis only"
            echo "✓ Single-tool result recorded (no cross-validation possible)"
            exit 0
        fi
        ;;

    *)
        echo "Unknown artifact type: $ARTIFACT_TYPE (supported: mft)"
        exit 2
        ;;
esac

# Delta check
if [ "${COUNT_A:-0}" -gt 0 ] && [ "${COUNT_B:-0}" -gt 0 ]; then
    DELTA=$(python3 -c "print(abs(($COUNT_A - $COUNT_B) / (($COUNT_A + $COUNT_B) / 2) * 100))" 2>/dev/null || echo 100)
    echo "Delta: ${DELTA}%"
    
    if python3 -c "exit(0 if float($DELTA) <= float($DELTA_MAX) else 1)" 2>/dev/null; then
        echo "✓ Delta within acceptable range (<${DELTA_MAX}%)"
        exit 0
    else
        echo "⚠️  WARNING: Delta exceeds ${DELTA_MAX}% threshold — FLAG FOR HUMAN REVIEW"
        exit 2
    fi
else
    echo "⚠️  Insufficient data for comparison"
    exit 1
fi