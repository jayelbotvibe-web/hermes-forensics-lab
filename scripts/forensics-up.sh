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
#   4. Runs session canary (validates all tools + environment)
#   5. Reports full system status
#
# After this, the forensics system is ready for any investigation.
# ============================================================================
# No 'set -e' — this is a bring-up script, it reports degradation, never aborts.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

FORENSICS_DIR="$FORENSICS_HOME"
LUKS_IMG="$FORENSICS_IMG"
LUKS_NAME="$FORENSICS_LUKS_NAME"
LUKS_KEYFILE="$FORENSICS_KEYFILE"
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
if ! is_enabled "$FORENSICS_VAULT_ENABLED"; then
    # Unencrypted storage — a deliberate choice for CTF/lab use.
    mkdir -p "$FORENSICS_DIR"/{cases,tools,scripts,fixtures,logs} 2>/dev/null
    echo -e "  ${YELLOW}⚠${NC}  Vault disabled — evidence is NOT encrypted at rest"
    echo "     $FORENSICS_DIR"
    LUKS_OPENED=true
elif [ ! -f "$LUKS_IMG" ] && ! mountpoint -q "$FORENSICS_DIR" 2>/dev/null; then
    echo -e "  ${RED}✗${NC} No evidence vault at $LUKS_IMG"
    echo ""
    echo -e "  ${YELLOW}Create one first:${NC}"
    echo "     bash scripts/create-evidence-vault.sh --size 60G"
    echo ""
    echo "  Or set FORENSICS_VAULT_ENABLED=false in your forensics.conf to"
    echo "  store evidence unencrypted."
    exit 1
elif mountpoint -q "$FORENSICS_DIR" 2>/dev/null; then
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
        if sudo cryptsetup open "$LUKS_IMG" "$LUKS_NAME" --key-file="$LUKS_KEYFILE" 2>/dev/null; then
            sudo mount /dev/mapper/"$LUKS_NAME" "$FORENSICS_DIR" 2>/dev/null && {
                echo -e "  ${GREEN}✓${NC} Opened and mounted"
                LUKS_OPENED=true
            } || echo -e "  ${RED}✗${NC} Mount failed after LUKS open"
        else
            echo -e "  ${YELLOW}⚠${NC}  Keyfile failed (wrong password?)"
        fi
    fi

    # No keyfile, or it did not work — fall back to an interactive passphrase.
    if ! $LUKS_OPENED; then
        echo "  Opening LUKS (enter your vault passphrase)..."
        if sudo cryptsetup open "$LUKS_IMG" "$LUKS_NAME"; then
            sudo mount /dev/mapper/"$LUKS_NAME" "$FORENSICS_DIR" 2>/dev/null && {
                echo -e "  ${GREEN}✓${NC} Opened and mounted"
                LUKS_OPENED=true
            } || echo -e "  ${RED}✗${NC} Mount failed after LUKS open"
        fi
    fi

    if ! $LUKS_OPENED; then
        echo ""
        echo -e "  ${RED}✗${NC} LUKS NOT MOUNTED — cannot proceed."
        echo ""
        echo -e "  ${YELLOW}To skip the passphrase prompt in future, enrol a keyfile:${NC}"
        echo "     head -c 4096 /dev/urandom > $LUKS_KEYFILE && chmod 600 $LUKS_KEYFILE"
        echo "     sudo cryptsetup luksAddKey $LUKS_IMG $LUKS_KEYFILE"
        echo ""
        echo "  Diagnose everything: bash scripts/forensics-doctor.sh"
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

SSH_READY=false
SIFT_SKIPPED=false

if ! sift_configured; then
    # Host-only is supported: Docker tools and MemProcFS still work.
    echo -e "  ${YELLOW}⚠${NC}  No SIFT VM configured — host-only mode"
    echo "     8 filesystem tools unavailable. To add a VM:"
    echo "       bash scripts/provision-sift.sh <vm-ip>"
    SIFT_SKIPPED=true
else
    if [ -z "$SIFT_VMX" ]; then
        echo -e "  ${CYAN}·${NC} No SIFT_VMX set — expecting the VM to be running already"
    elif ! command -v vmrun >/dev/null 2>&1; then
        echo -e "  ${YELLOW}⚠${NC}  vmrun not on PATH — cannot auto-start the VM"
    elif vmrun list 2>/dev/null | grep -qF "$SIFT_VMX"; then
        echo -e "  ${GREEN}✓${NC} VM already running"
    else
        echo "  Starting VM (nogui)..."
        if vmrun -T ws start "$SIFT_VMX" nogui 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} VM started"
        else
            echo -e "  ${YELLOW}⚠${NC}  vmrun could not start $SIFT_VMX"
        fi
    fi
fi

# Wait for SSH — with retry logic
$SIFT_SKIPPED || for retry in $(seq 1 $SSH_RETRIES); do
    [ "$retry" -gt 1 ] && echo "  Retry $retry/$SSH_RETRIES..."
    echo -n "  Waiting for SSH"
    for _ in $(seq 1 $SSH_WAIT_MAX); do
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
    if [ "$retry" -lt "$SSH_RETRIES" ] && ! $SSH_READY && [ -n "$SIFT_VMX" ]; then
        echo -e "  ${YELLOW}⚠${NC}  SSH timeout — restarting VM..."
        vmrun -T ws stop "$SIFT_VMX" hard 2>/dev/null || true
        sleep 5
        vmrun -T ws start "$SIFT_VMX" nogui 2>/dev/null || true
    fi
done
$SIFT_SKIPPED || echo ""

if $SSH_READY; then
    SIFT_UPTIME=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$SIFT_USER@$SIFT_HOST" 'uptime -p' 2>/dev/null || echo "unknown")
    SIFT_IP=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$SIFT_USER@$SIFT_HOST" 'hostname -I' 2>/dev/null || echo "unknown")
    echo -e "  ${GREEN}✓${NC} SSH ready — ${SIFT_UPTIME} — IP: ${SIFT_IP}"
elif ! $SIFT_SKIPPED; then
    echo -e "  ${RED}✗${NC} SIFT VM SSH unreachable after ${SSH_RETRIES} attempt(s)"
    echo "  Check manually:  bash scripts/sift-exec.sh whoami"
    echo "  Diagnose:        bash scripts/forensics-doctor.sh"
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

CANARY_RC=1
if CANARY_SCRIPT="$(forensics_script session-canary.sh)"; then
    bash "$CANARY_SCRIPT"
    CANARY_RC=$?
else
    echo -e "  ${RED}✗${NC} session-canary.sh not found in $FORENSICS_REPO/scripts or $FORENSICS_HOME/scripts"
    echo "     Re-sync the lab files: ./install.sh --profile-only"
fi

# ══════════════════════════════════════════════════════════════════════════
# Final Report
# ══════════════════════════════════════════════════════════════════════════

echo ""
if is_enabled "$FORENSICS_VAULT_ENABLED"; then
    LUKS_OK=$(mountpoint -q "$FORENSICS_DIR" 2>/dev/null && echo true || echo false)
else
    LUKS_OK=$([ -d "$FORENSICS_DIR" ] && echo true || echo false)
fi
DOCKER_OK=$(docker info >/dev/null 2>&1 && echo true || echo false)
# In host-only mode an absent VM is the configured state, not a failure.
SIFT_OK=$($SIFT_SKIPPED && echo true || echo "$SSH_READY")

if [ $CANARY_RC -eq 0 ] && $SIFT_OK && $LUKS_OK && $DOCKER_OK; then
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
    echo -n "  Evidence:  "; $LUKS_OK && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}"
    echo -n "  SIFT VM:   "; $SIFT_SKIPPED && echo -e "${YELLOW}host-only${NC}" \
        || { $SSH_READY && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}"; }
    echo -n "  Docker:    "; $DOCKER_OK && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}"
    echo -n "  Canary:    "; [ $CANARY_RC -eq 0 ] && echo -e "${GREEN}OK${NC}" || echo -e "${RED}FAIL${NC}"
    echo ""
    echo -e "  ${DIM}For per-item fixes: bash scripts/forensics-doctor.sh${NC}"
fi

echo ""
echo "  Active cases: $(ls "$FORENSICS_DIR/cases/" 2>/dev/null | wc -l)"
echo "  Evidence root: $FORENSICS_DIR/cases/"
echo ""
