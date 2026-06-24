#!/bin/bash
# Session canary — validate ALL forensic tools before investigation
# Run: bash /home/niel/forensics/scripts/session-canary.sh
# Exit 0 = all operational, non-zero = some tools degraded
set -uo pipefail

FIXTURES_DIR="/home/niel/forensics/fixtures"
SIFT_EXEC="/home/niel/forensics/scripts/sift-exec.sh"
DEGRADED=()
PASSED=0
FAILED=0

echo "=== Forensics Session Canary ==="
echo "Time: $(date -Iseconds)"
echo ""

# ── Docker tools ──
for tool in volatility3 plaso mft-tools; do
    echo -n "[docker:$tool] "
    IMAGE="forensics-${tool}:latest"
    case $tool in
        mft-tools)
            if docker run --rm "$IMAGE" python3 -c "import analyzemft; print('ok')" > /dev/null 2>&1; then
                echo "PASS"; ((PASSED++))
            else
                echo "FAIL — DEGRADED"; ((FAILED++)); DEGRADED+=("$tool")
            fi ;;
        *)
            if docker run --rm "$IMAGE" --help >/dev/null 2>&1; then
                echo "PASS"; ((PASSED++))
            else
                echo "FAIL — DEGRADED"; ((FAILED++)); DEGRADED+=("$tool")
            fi ;;
    esac
done

# ── SIFT VM connectivity ──
echo -n "[sift:connectivity] "
if $SIFT_EXEC "echo OK" > /dev/null 2>&1; then
    echo "PASS"; ((PASSED++))
else
    echo "FAIL — SIFT VM unreachable"; ((FAILED++)); DEGRADED+=("sift-vm")
fi

# ── SIFT native tools ──
if [ ${#DEGRADED[@]} -eq 0 ] || [[ ! " ${DEGRADED[*]} " =~ "sift-vm" ]]; then
    for tool in sleuthkit foremost dc3dd regripper hashdeep; do
        echo -n "[sift:$tool] "
        case $tool in
            sleuthkit) cmd="fls -V 2>&1 | head -1" ;;
            foremost)  cmd="foremost -V 2>&1" ;;
            dc3dd)     cmd="dc3dd --version 2>&1" ;;
            regripper) cmd="which regripper 2>&1" ;;
            hashdeep)  cmd="hashdeep -V 2>&1" ;;
        esac
        if $SIFT_EXEC "$cmd" > /dev/null 2>&1; then
            echo "PASS"; ((PASSED++))
        else
            echo "FAIL — DEGRADED"; ((FAILED++)); DEGRADED+=("$tool")
        fi
    done
fi

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
if [ ${#DEGRADED[@]} -gt 0 ]; then
    echo "⚠️  DEGRADED: ${DEGRADED[*]}"
    echo "DEGRADED tools are TRIAGE-ONLY — not for evidentiary work."
    exit 1
fi
echo "✓ All tools operational"
exit 0
