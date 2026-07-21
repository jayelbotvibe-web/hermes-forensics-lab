#!/bin/bash
# Session Canary — validates the 12 forensic tools (Tool Inventory) + environment
# TOOLS  = evidentiary tools only: 3 Docker images + MemProcFS + 8 SIFT-native tools
# ENV    = infrastructure: Docker daemon, LUKS vault, SIFT SSH path, directories
# Counts here are the source of truth for project-metadata.yaml canary_checks.
# Run: bash session-canary.sh
# Exit 0 = all operational, non-zero = degraded
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

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
LUKS_DEVICE="${FORENSICS_LUKS_DEVICE:-/dev/mapper/$FORENSICS_LUKS_NAME}"
ENV_TOTAL=$((ENV_TOTAL + 1))
if ! is_enabled "$FORENSICS_VAULT_ENABLED"; then
    # Explicitly opted out — unencrypted storage is a choice, not a degradation.
    if [ -d "$FORENSICS_HOME" ]; then
        echo "INFO — vault disabled, using plain filesystem"; ENV_PASSED=$((ENV_PASSED + 1))
    else
        echo "FAIL — $FORENSICS_HOME does not exist"; DEGRADED+=("luks")
    fi
elif [ -e "$LUKS_DEVICE" ] && mountpoint -q "$FORENSICS_HOME" 2>/dev/null; then
    echo "PASS (mounted)"; ENV_PASSED=$((ENV_PASSED + 1))
elif [ -e "$LUKS_DEVICE" ]; then
    echo "WARN — LUKS open but not mounted"; DEGRADED+=("luks")
elif [ -f "$FORENSICS_IMG" ]; then
    echo "WARN — vault exists but is closed (run forensics-up.sh)"; DEGRADED+=("luks")
else
    echo "FAIL — no vault (run scripts/create-evidence-vault.sh)"; DEGRADED+=("luks")
fi

# SIFT VM connectivity (tool access path — infrastructure, not a tool)
SIFT_REACHABLE=false
echo -n "[env:sift-ssh] "
ENV_TOTAL=$((ENV_TOTAL + 1))
if ! sift_configured; then
    # Host-only is a supported configuration, not a fault.
    echo "SKIP — no SIFT VM configured (host-only mode)"
    ENV_PASSED=$((ENV_PASSED + 1))
else
    # Word splitting is intended: sift_ssh_opts emits one option per line.
    read -r -a SSH_OPTS <<< "$(sift_ssh_opts | tr '\n' ' ')"
    if SSH_OUT=$(ssh "${SSH_OPTS[@]}" "$SIFT_USER@$SIFT_HOST" "echo ok" 2>&1); then
        SIFT_REACHABLE=true
        ENV_PASSED=$((ENV_PASSED + 1))
        echo "PASS ($SIFT_HOST)"
    else
        echo "DEGRADED ($SSH_OUT)"
        DEGRADED+=("sift-ssh")
    fi
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
for img in "$IMAGE_VOLATILITY3" "$IMAGE_PLASO" "$IMAGE_MFT_TOOLS"; do
    echo -n "[docker:$img] "
    TOOLS_TOTAL=$((TOOLS_TOTAL + 1))
    if docker image inspect "$img" >/dev/null 2>&1; then echo "PASS"; TOOLS_PASSED=$((TOOLS_PASSED + 1))
    else echo "FAIL"; DEGRADED+=("docker-$img"); fi
done

# 4. MemProcFS — verify the binary AND its actual version (no hardcoded claims)
echo -n "[host:memprocfs] "
TOOLS_TOTAL=$((TOOLS_TOTAL + 1))
MPF_BIN="$MEMPROCFS_BIN"
MPF_EXPECTED="$MEMPROCFS_EXPECTED_VERSION"   # keep in sync with tools/tool-catalog.yaml
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
SIFT_EXEC="$(forensics_script sift-exec.sh || echo "$FORENSICS_HOME/scripts/sift-exec.sh")"
for entry in "${SIFT_TOOLS[@]}"; do
    name="${entry%%:*}"
    probe="${entry#*:}"
    echo -n "[sift:$name] "
    if ! sift_configured; then
        # Host-only: these tools are out of scope, so they are not counted
        # against the inventory at all. An absent tool you never asked for
        # is not a degraded tool.
        echo "SKIP (host-only mode)"
        continue
    fi
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
