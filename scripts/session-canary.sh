#!/bin/bash
# Session Canary — validates the 12 forensic tools (Tool Inventory) + environment
# TOOLS  = evidentiary tools only: 3 Docker images + MemProcFS + 8 SIFT-native tools
# ENV    = infrastructure: Docker daemon, LUKS vault, SIFT SSH path, directories
# Counts here are the source of truth for project-metadata.yaml canary_checks.
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
# ENVIRONMENT — infrastructure checks (not forensic tools)
# Run first: SSH and Docker daemon results gate tool probes below.
# ═══════════════════════════════════════════════════════════════

# Docker daemon
echo -n "[env:docker-daemon] "
ENV_TOTAL=$((ENV_TOTAL + 1))
if docker ps >/dev/null 2>&1; then echo "PASS"; ENV_PASSED=$((ENV_PASSED + 1))
else echo "FAIL"; DEGRADED+=("docker-daemon"); fi

# LUKS vault (evidence-at-rest encryption — infrastructure, not a tool)
echo -n "[env:luks] "
LUKS_DEVICE="${FORENSICS_LUKS_DEVICE:-/dev/mapper/forensics-vault}"
ENV_TOTAL=$((ENV_TOTAL + 1))
if [ -e "$LUKS_DEVICE" ] && mountpoint -q "$FORENSICS_HOME" 2>/dev/null; then
    echo "PASS (mounted)"; ENV_PASSED=$((ENV_PASSED + 1))
elif [ -e "$LUKS_DEVICE" ]; then
    echo "WARN — LUKS exists but not mounted"; DEGRADED+=("luks")
elif [ -d "$FORENSICS_HOME" ]; then
    echo "INFO — no separate vault, using root filesystem"; ENV_PASSED=$((ENV_PASSED + 1))
else
    echo "FAIL"; DEGRADED+=("luks")
fi

# SIFT VM connectivity (tool access path — infrastructure, not a tool)
SIFT_REACHABLE=false
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i ${SSH_IDENTITY:-$HOME/.ssh/id_rsa}"
echo -n "[env:sift-ssh] "
ENV_TOTAL=$((ENV_TOTAL + 1))
# shellcheck disable=SC2086
if SSH_OUT=$(ssh $SSH_OPTS sansforensics@"${SIFT_HOST:-172.16.146.128}" "echo ok" 2>&1); then
    SIFT_REACHABLE=true
    ENV_PASSED=$((ENV_PASSED + 1))
    echo "PASS (${SIFT_HOST:-172.16.146.128})"
else
    echo "DEGRADED ($SSH_OUT)"
    DEGRADED+=("sift-ssh")
fi

# Directories
for dir in cases tools scripts fixtures logs; do
    echo -n "[env:dir-$dir] "
    ENV_TOTAL=$((ENV_TOTAL + 1))
    if [ -d "$FORENSICS_HOME/$dir" ]; then echo "PASS"; ENV_PASSED=$((ENV_PASSED + 1))
    else echo "FAIL"; DEGRADED+=("dir-$dir"); fi
done

echo ""

# ═══════════════════════════════════════════════════════════════
# TOOLS — the 12 forensic tools that produce evidentiary output
# Must match the README Tool Inventory 1:1.
# ═══════════════════════════════════════════════════════════════

# 1-3. Docker images (volatility3, plaso, mft-tools)
for img in "forensics-volatility3:2.7.0" "forensics-plaso:20240512" "forensics-mft-tools:1.2.0.0"; do
    echo -n "[docker:$img] "
    TOOLS_TOTAL=$((TOOLS_TOTAL + 1))
    if docker image inspect "$img" >/dev/null 2>&1; then echo "PASS"; TOOLS_PASSED=$((TOOLS_PASSED + 1))
    else echo "FAIL"; DEGRADED+=("docker-$img"); fi
done

# 4. MemProcFS — verify the binary AND its actual version (no hardcoded claims)
echo -n "[host:memprocfs] "
TOOLS_TOTAL=$((TOOLS_TOTAL + 1))
MPF_BIN="${MEMPROCFS_BIN:-$HOME/memprocfs/memprocfs}"
MPF_EXPECTED="${MEMPROCFS_EXPECTED_VERSION:-5.17.8}"   # keep in sync with tools/tool-catalog.yaml
if [ -x "$MPF_BIN" ]; then
    # MemProcFS prints its version banner on startup; probe without mounting anything
    MPF_VER=$(timeout 10 "$MPF_BIN" -version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    if [ -z "$MPF_VER" ]; then
        MPF_VER=$(timeout 10 "$MPF_BIN" 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    fi
    if [ "$MPF_VER" = "$MPF_EXPECTED" ]; then
        echo "PASS (v$MPF_VER)"; TOOLS_PASSED=$((TOOLS_PASSED + 1))
    elif [ -n "$MPF_VER" ]; then
        echo "WARN — v$MPF_VER installed but catalog pins v$MPF_EXPECTED"
        DEGRADED+=("memprocfs-version")
    else
        echo "WARN — executable but version unverifiable (expected v$MPF_EXPECTED)"
        DEGRADED+=("memprocfs-version")
    fi
else
    echo "FAIL"; DEGRADED+=("memprocfs")
fi

# 5-12. SIFT VM native tools — all 8 from the Tool Inventory
# Format: inventory_name:probe_command
SIFT_TOOLS=(
    "sleuthkit:fls"
    "foremost:foremost"
    "photorec:photorec"
    "dc3dd:dc3dd"
    "ddrescue:ddrescue"
    "regripper:/usr/lib/regripper/rip.pl"
    "hashdeep:hashdeep"
    "tshark:tshark"
)
SIFT_EXEC="$FORENSICS_HOME/scripts/sift-exec.sh"
for entry in "${SIFT_TOOLS[@]}"; do
    name="${entry%%:*}"
    probe="${entry#*:}"
    echo -n "[sift:$name] "
    TOOLS_TOTAL=$((TOOLS_TOTAL + 1))
    if ! $SIFT_REACHABLE; then
        # VM unreachable: tools still count toward the total — an unreachable
        # tool is a degraded tool, not an invisible one.
        echo "DEGRADED (SIFT unreachable)"
        DEGRADED+=("sift-$name")
        continue
    fi
    PASS=false
    for attempt in 1 2; do
        if bash "$SIFT_EXEC" "command -v $probe" >/dev/null 2>&1; then
            PASS=true; break
        fi
        [ $attempt -lt 2 ] && sleep 2
    done
    if $PASS; then echo "PASS"; TOOLS_PASSED=$((TOOLS_PASSED + 1))
    else echo "DEGRADED"; DEGRADED+=("sift-$name"); fi
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
