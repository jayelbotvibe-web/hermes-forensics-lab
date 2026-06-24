#!/bin/bash
# ============================================================================
# forensics-up.sh — One-command forensics environment bring-up.
#
# Usage:  bash ~/forensics/scripts/forensics-up.sh
#
# What it does:
#   1. Opens and mounts the LUKS evidence volume (if not already mounted)
#   2. Starts the SIFT Workstation VM (if not running) and waits for SSH
#   3. Verifies Docker is running
#   4. Runs session canary (validates all 9 tools)
#   5. Reports full system status
#
# After this, the forensics system is ready for any investigation.
# ============================================================================
# No 'set -e' — this is a bring-up script, it reports degradation, never aborts.
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

FORENSICS_DIR="/home/niel/forensics"
LUKS_IMG="/home/niel/forensics.img"
LUKS_NAME="forensics_crypt"
LUKS_KEYFILE="${FORENSICS_KEYFILE:-/home/niel/.forensics-keyfile}"
SIFT_VMX="/home/niel/vmware/SIFT/SIFT.vmx"
SIFT_HOST="172.16.146.128"
SIFT_USER="sansforensics"
SSH_WAIT_MAX=45     # iterations × 4s = 3 min
SSH_RETRIES=2       # retry cycles if VM doesn't come up

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Hermes Forensics — Environment Bring-Up    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════
# Phase 1: LUKS Volume
# ══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[1/4] LUKS Evidence Volume${NC}"

LUKS_OPENED=false
if mountpoint -q "$FORENSICS_DIR" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Already mounted at $FORENSICS_DIR"
    LUKS_OPENED=true
elif sudo cryptsetup status "$LUKS_NAME" >/dev/null 2>&1; then
    # Container is open but not mounted — just mount it
    echo "  LUKS open but not mounted — mounting..."
    sudo mount /dev/mapper/"$LUKS_NAME" "$FORENSICS_DIR" 2>/dev/null && {
        echo -e "  ${GREEN}✓${NC} Mounted"
        LUKS_OPENED=true
    } || echo -e "  ${RED}✗${NC} Mount failed"
else
    # Try keyfile first
    if [ -f "$LUKS_KEYFILE" ]; then
        echo "  Opening LUKS with keyfile..."
        sudo cryptsetup open "$LUKS_IMG" "$LUKS_NAME" --key-file="$LUKS_KEYFILE" 2>/dev/null
        if [ $? -eq 0 ]; then
            sudo mount /dev/mapper/"$LUKS_NAME" "$FORENSICS_DIR" 2>/dev/null && {
                echo -e "  ${GREEN}✓${NC} Opened and mounted"
                LUKS_OPENED=true
            } || echo -e "  ${RED}✗${NC} Mount failed after LUKS open"
        else
            echo -e "  ${YELLOW}⚠${NC}  Keyfile failed (wrong password?)"
        fi
    fi

    # If keyfile failed or doesn't exist, prompt user
    if ! $LUKS_OPENED; then
        echo ""
        echo -e "  ${YELLOW}LUKS not mounted. To fix:${NC}"
        echo "     echo -n '<password>' > ~/.forensics-keyfile && chmod 600 ~/.forensics-keyfile"
        echo "     Then re-run this script."
        echo ""
        echo -e "  ${RED}✗${NC} LUKS NOT MOUNTED — cannot proceed."
        exit 1
    fi
fi

if $LUKS_OPENED; then
    df -h "$FORENSICS_DIR" 2>/dev/null | tail -1 | awk '{printf "  %s used / %s total\n", $3, $2}'
fi

# ══════════════════════════════════════════════════════════════════════════
# Phase 2: SIFT VM
# ══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}[2/4] SIFT Workstation VM${NC}"

if vmrun list 2>/dev/null | grep -q "SIFT.vmx"; then
    echo -e "  ${GREEN}✓${NC} VM already running"
else
    echo "  Starting VM (nogui)..."
    if vmrun -T ws start "$SIFT_VMX" nogui 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} VM started"
    else
        echo -e "  ${YELLOW}⚠${NC}  vmrun failed — is VMware Workstation installed?"
    fi
fi

# Wait for SSH — with retry logic
SSH_READY=false
for retry in $(seq 1 $SSH_RETRIES); do
    [ $retry -gt 1 ] && echo "  Retry $retry/$SSH_RETRIES..."
    echo -n "  Waiting for SSH"
    for i in $(seq 1 $SSH_WAIT_MAX); do
        if ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
               -o BatchMode=yes "$SIFT_USER@$SIFT_HOST" 'true' >/dev/null 2>&1; then
            SSH_READY=true
            break 2
        fi
        echo -n "."
        sleep 4
    done
    echo ""
    # If first attempt failed, try restarting the VM
    if [ $retry -lt $SSH_RETRIES ] && ! $SSH_READY; then
        echo -e "  ${YELLOW}⚠${NC}  SSH timeout — restarting VM..."
        vmrun -T ws stop "$SIFT_VMX" hard 2>/dev/null || true
        sleep 5
        vmrun -T ws start "$SIFT_VMX" nogui 2>/dev/null || true
    fi
done
echo ""

if $SSH_READY; then
    SIFT_UPTIME=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$SIFT_USER@$SIFT_HOST" 'uptime -p' 2>/dev/null || echo "unknown")
    SIFT_IP=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$SIFT_USER@$SIFT_HOST" 'hostname -I' 2>/dev/null || echo "unknown")
    echo -e "  ${GREEN}✓${NC} SSH ready — ${SIFT_UPTIME} — IP: ${SIFT_IP}"
else
    echo -e "  ${RED}✗${NC} SIFT VM SSH unreachable after ${SSH_RETRIES} attempt(s)"
    echo "  Run 'bash ~/forensics/scripts/sift-exec.sh whoami' to check manually"
fi

# ══════════════════════════════════════════════════════════════════════════
# Phase 3: Docker
# ══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}[3/4] Docker Runtime${NC}"

if docker info >/dev/null 2>&1; then
    DOCKER_IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -c forensics- || echo 0)
    echo -e "  ${GREEN}✓${NC} Docker running — ${DOCKER_IMAGES} forensic images"
    docker images --format '  {{.Repository}}:{{.Tag}} ({{.Size}})' 2>/dev/null | grep forensics- || true
else
    echo -e "  ${RED}✗${NC} Docker not accessible — try: sudo systemctl start docker"
fi

# ══════════════════════════════════════════════════════════════════════════
# Phase 4: Session Canary
# ══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}[4/4] Session Canary${NC}"
echo ""

CANARY_SCRIPT="$FORENSICS_DIR/scripts/session-canary.sh"
CANARY_RC=1
if [ -x "$CANARY_SCRIPT" ]; then
    bash "$CANARY_SCRIPT"
    CANARY_RC=$?
else
    echo -e "  ${RED}✗${NC} Canary script not found at $CANARY_SCRIPT"
fi

# ══════════════════════════════════════════════════════════════════════════
# Final Report
# ══════════════════════════════════════════════════════════════════════════

echo ""
LUKS_OK=$(mountpoint -q "$FORENSICS_DIR" 2>/dev/null && echo true || echo false)
DOCKER_OK=$(docker info >/dev/null 2>&1 && echo true || echo false)

if [ $CANARY_RC -eq 0 ] && $SSH_READY && $LUKS_OK && $DOCKER_OK; then
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   ✓ FORENSICS SYSTEM READY                   ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
else
    echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║   ⚠  SYSTEM PARTIALLY DEGRADED              ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Component  Status"
    echo "  ─────────  ──────"
    echo -n "  LUKS:      "; $LUKS_OK && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}"
    echo -n "  SIFT VM:   "; $SSH_READY && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}"
    echo -n "  Docker:    "; $DOCKER_OK && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}"
    echo -n "  Canary:    "; [ $CANARY_RC -eq 0 ] && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}"
fi

echo ""
echo "  Active cases: $(ls "$FORENSICS_DIR/cases/" 2>/dev/null | wc -l)"
echo "  Evidence root: $FORENSICS_DIR/cases/"
echo ""
