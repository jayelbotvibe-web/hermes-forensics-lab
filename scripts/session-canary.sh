#!/bin/bash
# Session Canary — validates all 3 forensics runtimes
# Run: bash session-canary.sh
# Exit 0 = all operational, non-zero = degraded
set -uo pipefail

FORENSICS_HOME="${FORENSICS_HOME:-$HOME/forensics}"
DEGRADED=()
PASSED=0
FAILED=0

echo "=== Forensics Session Canary ==="
echo "Time: $(date -Iseconds)"
echo "Host: $(hostname)"
echo ""

# 1. LUKS vault (optional)
echo -n "[luks] "
LUKS_DEVICE="${FORENSICS_LUKS_DEVICE:-/dev/mapper/forensics-vault}"
if [ -e "$LUKS_DEVICE" ] && mountpoint -q "$FORENSICS_HOME" 2>/dev/null; then
    echo "PASS (mounted)"; ((PASSED++))
elif [ -e "$LUKS_DEVICE" ]; then
    echo "WARN — LUKS exists but not mounted"; DEGRADED+=("luks")
elif [ -d "$FORENSICS_HOME" ]; then
    echo "INFO — no separate vault, using root filesystem"; ((PASSED++))
else
    echo "FAIL"; ((FAILED++)); DEGRADED+=("luks")
fi

# 2. Docker daemon + images
echo -n "[docker:daemon] "
if docker ps >/dev/null 2>&1; then echo "PASS"; ((PASSED++))
else echo "FAIL"; ((FAILED++)); DEGRADED+=("docker-daemon"); fi

for img in "forensics-volatility3:2.7.0" "forensics-plaso:20240512" "forensics-mft-tools:1.2.0.0"; do
    echo -n "[docker:$img] "
    if docker image inspect "$img" >/dev/null 2>&1; then echo "PASS"; ((PASSED++))
    else echo "FAIL"; ((FAILED++)); DEGRADED+=("docker-$img"); fi
done

# 3. MemProcFS
echo -n "[host:memprocfs] "
if [ -x "${MEMPROCFS_BIN:-$HOME/memprocfs/memprocfs}" ]; then echo "PASS (v5.17.8)"; ((PASSED++))
else echo "FAIL"; ((FAILED++)); DEGRADED+=("memprocfs"); fi

# 4. SIFT VM connectivity
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i ${SSH_IDENTITY:-$HOME/.ssh/id_rsa}"
echo -n "[sift:ssh] "
SSH_OUT=$(ssh $SSH_OPTS sansforensics@${SIFT_HOST:-172.16.146.128} "echo ok" 2>&1)
if [ $? -eq 0 ]; then echo "PASS (${SIFT_HOST:-172.16.146.128})"; ((PASSED++))
else echo "DEGRADED ($SSH_OUT)"; DEGRADED+=("sift-ssh"); fi

# 5. SIFT VM tools
if [[ ! " ${DEGRADED[*]} " =~ "sift-ssh" ]]; then
    SIFT_TOOLS=("fls" "foremost" "dc3dd" "/usr/lib/regripper/rip.pl" "hashdeep" "tshark")
    SIFT_EXEC="$FORENSICS_HOME/scripts/sift-exec.sh"
    for tool in "${SIFT_TOOLS[@]}"; do
        echo -n "[sift:${tool##*/}] "
        PASS=false
        for attempt in 1 2; do
            if bash "$SIFT_EXEC" "command -v $tool" >/dev/null 2>&1; then
                PASS=true; break
            fi
            [ $attempt -lt 2 ] && sleep 2
        done
        if $PASS; then echo "PASS"; ((PASSED++))
        else echo "DEGRADED"; DEGRADED+=("sift-${tool##*/}"); fi
    done
else
    echo "[sift] All SIFT tools SKIPPED — VM unreachable"
fi

# 6. Directories
for dir in cases tools scripts fixtures logs; do
    echo -n "[dir:$dir] "
    if [ -d "$FORENSICS_HOME/$dir" ]; then echo "PASS"; ((PASSED++))
    else echo "FAIL"; ((FAILED++)); DEGRADED+=("dir-$dir"); fi
done

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
if [ ${#DEGRADED[@]} -gt 0 ]; then
    echo "⚠️  DEGRADED: ${DEGRADED[*]}"
    echo "⚠️  DEGRADED tools are TRIAGE-ONLY — not for evidentiary findings."
    echo "Recovery: agent dispatch or manual fix"
    exit 1
fi
echo "✓ All runtimes operational — ready for investigation"
exit 0
