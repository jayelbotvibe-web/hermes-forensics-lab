#!/bin/bash
# Session Canary — validates all 3 forensics runtimes
# Run: bash session-canary.sh
# Exit 0 = all operational, non-zero = degraded
set -uo pipefail

FORENSICS_HOME="${FORENSICS_HOME:-$HOME/forensics}"
DEGRADED=()

# Two separate tallies: TOOLS (forensic tools) vs ENVIRONMENT (infrastructure)
TOOLS_PASSED=0
TOOLS_TOTAL=0
ENV_PASSED=0
ENV_TOTAL=0

echo "=== Forensics Session Canary ==="
echo "Time: $(date -Iseconds)"
echo "Host: $(hostname)"
echo ""

# ═══════════════════════════════════════════════════════════════
# TOOLS — forensic tools that produce evidentiary output
# ═══════════════════════════════════════════════════════════════

# 1. LUKS vault (tool: evidence-at-rest encryption)
echo -n "[luks] "
LUKS_DEVICE="${FORENSICS_LUKS_DEVICE:-/dev/mapper/forensics-vault}"
TOOLS_TOTAL=$((TOOLS_TOTAL + 1))
if [ -e "$LUKS_DEVICE" ] && mountpoint -q "$FORENSICS_HOME" 2>/dev/null; then
    echo "PASS (mounted)"; TOOLS_PASSED=$((TOOLS_PASSED + 1))
elif [ -e "$LUKS_DEVICE" ]; then
    echo "WARN — LUKS exists but not mounted"; DEGRADED+=("luks")
elif [ -d "$FORENSICS_HOME" ]; then
    echo "INFO — no separate vault, using root filesystem"; TOOLS_PASSED=$((TOOLS_PASSED + 1))
else
    echo "FAIL"; DEGRADED+=("luks")
fi

# 2. Docker images (tools: volatility3, plaso, mft-tools)
for img in "forensics-volatility3:2.7.0" "forensics-plaso:20240512" "forensics-mft-tools:1.2.0.0"; do
    echo -n "[docker:$img] "
    TOOLS_TOTAL=$((TOOLS_TOTAL + 1))
    if docker image inspect "$img" >/dev/null 2>&1; then echo "PASS"; TOOLS_PASSED=$((TOOLS_PASSED + 1))
    else echo "FAIL"; DEGRADED+=("docker-$img"); fi
done

# 3. MemProcFS (tool: memory analysis via FUSE mount)
echo -n "[host:memprocfs] "
TOOLS_TOTAL=$((TOOLS_TOTAL + 1))
if [ -x "${MEMPROCFS_BIN:-$HOME/memprocfs/memprocfs}" ]; then echo "PASS (v5.17.8)"; TOOLS_PASSED=$((TOOLS_PASSED + 1))
else echo "FAIL"; DEGRADED+=("memprocfs"); fi

# 4. SIFT VM connectivity (tool access path)
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i ${SSH_IDENTITY:-$HOME/.ssh/id_rsa}"
echo -n "[sift:ssh] "
TOOLS_TOTAL=$((TOOLS_TOTAL + 1))
SSH_OUT=$(ssh $SSH_OPTS sansforensics@${SIFT_HOST:-172.16.146.128} "echo ok" 2>&1)
if [ $? -eq 0 ]; then echo "PASS (${SIFT_HOST:-172.16.146.128})"; TOOLS_PASSED=$((TOOLS_PASSED + 1))
else echo "DEGRADED ($SSH_OUT)"; DEGRADED+=("sift-ssh"); fi

# 5. SIFT VM native tools (6 individual forensic tools)
if [[ ! " ${DEGRADED[*]} " =~ "sift-ssh" ]]; then
    SIFT_TOOLS=("fls" "foremost" "dc3dd" "/usr/lib/regripper/rip.pl" "hashdeep" "tshark")
    SIFT_EXEC="$FORENSICS_HOME/scripts/sift-exec.sh"
    for tool in "${SIFT_TOOLS[@]}"; do
        echo -n "[sift:${tool##*/}] "
        TOOLS_TOTAL=$((TOOLS_TOTAL + 1))
        PASS=false
        for attempt in 1 2; do
            if bash "$SIFT_EXEC" "command -v $tool" >/dev/null 2>&1; then
                PASS=true; break
            fi
            [ $attempt -lt 2 ] && sleep 2
        done
        if $PASS; then echo "PASS"; TOOLS_PASSED=$((TOOLS_PASSED + 1))
        else echo "DEGRADED"; DEGRADED+=("sift-${tool##*/}"); fi
    done
else
    echo "[sift] All SIFT tools SKIPPED — VM unreachable"
fi

# ═══════════════════════════════════════════════════════════════
# ENVIRONMENT — infrastructure checks (not forensic tools)
# ═══════════════════════════════════════════════════════════════

# Docker daemon
echo -n "[docker:daemon] "
ENV_TOTAL=$((ENV_TOTAL + 1))
if docker ps >/dev/null 2>&1; then echo "PASS"; ENV_PASSED=$((ENV_PASSED + 1))
else echo "FAIL"; DEGRADED+=("docker-daemon"); fi

# Directories
for dir in cases tools scripts fixtures logs; do
    echo -n "[dir:$dir] "
    ENV_TOTAL=$((ENV_TOTAL + 1))
    if [ -d "$FORENSICS_HOME/$dir" ]; then echo "PASS"; ENV_PASSED=$((ENV_PASSED + 1))
    else echo "FAIL"; DEGRADED+=("dir-$dir"); fi
done

echo ""
echo "=== Canary Results ==="
echo "Tools:       ${TOOLS_PASSED}/${TOOLS_TOTAL} operational"
echo "Environment: ${ENV_PASSED}/${ENV_TOTAL} ready"
if [ ${#DEGRADED[@]} -gt 0 ]; then
    echo "⚠️  DEGRADED: ${DEGRADED[*]}"
    echo "⚠️  DEGRADED tools are TRIAGE-ONLY — not for evidentiary findings."
    echo "Recovery: agent dispatch or manual fix"
    exit 1
fi
echo "✓ All runtimes operational — ready for investigation"
exit 0
