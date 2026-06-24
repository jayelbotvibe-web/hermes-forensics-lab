#!/bin/bash
# ============================================================================
# forensics-down.sh — Clean forensics system shutdown.
#
# Usage:  bash ~/forensics/scripts/forensics-down.sh
#         bash ~/forensics/scripts/forensics-down.sh --force   (skip confirmation)
#
# What it does:
#   1. Unmounts all MemProcFS mounts
#   2. Gracefully stops the SIFT Workstation VM
#   3. Locks the LUKS evidence volume
# ============================================================================
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

FORENSICS_DIR="/home/niel/forensics"
LUKS_NAME="forensics_crypt"
SIFT_VMX="/home/niel/vmware/SIFT/SIFT.vmx"
FORCE=false

# ── Args ────────────────────────────────────────────────────────────────

case "${1:-}" in
    --force|-f) FORCE=true ;;
    --help|-h)
        echo "Usage: bash forensics-down.sh [--force]"
        echo ""
        echo "  --force, -f    Skip confirmation prompt"
        echo "  --help, -h     Show this help"
        exit 0 ;;
esac

# ── Confirmation ────────────────────────────────────────────────────────

if ! $FORCE; then
    echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║   ⚠  This will SHUT DOWN the forensics system ║${NC}"
    echo -e "${YELLOW}║      - Unmount MemProcFS                      ║${NC}"
    echo -e "${YELLOW}║      - Stop SIFT VM                           ║${NC}"
    echo -e "${YELLOW}║      - Lock LUKS evidence volume              ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -n "  Proceed? [y/N] "
    read -r REPLY
    case "$REPLY" in
        [Yy]|[Yy][Ee][Ss]) ;;
        *) echo "  Aborted."; exit 0 ;;
    esac
    echo ""
fi

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Hermes Forensics — System Shutdown         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════
# Step 1: Unmount MemProcFS mounts
# ══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[1/3] Unmounting MemProcFS${NC}"
UNMOUNTED=0
for mp in /home/niel/forensics/mounts/*/; do
    mp="${mp%/}"
    if mountpoint -q "$mp" 2>/dev/null; then
        fusermount -u "$mp" 2>/dev/null && {
            echo -e "  ${GREEN}✓${NC} Unmounted $mp"
            ((UNMOUNTED++))
        } || echo -e "  ${RED}✗${NC} Failed to unmount $mp"
    fi
done
# Also check /mnt/mem as fallback
if mountpoint -q /mnt/mem 2>/dev/null; then
    fusermount -u /mnt/mem 2>/dev/null && {
        echo -e "  ${GREEN}✓${NC} Unmounted /mnt/mem"
        ((UNMOUNTED++))
    } || echo -e "  ${RED}✗${NC} Failed to unmount /mnt/mem"
fi
[ $UNMOUNTED -eq 0 ] && echo "  (no MemProcFS mounts found)"

# ══════════════════════════════════════════════════════════════════════════
# Step 2: Stop SIFT VM
# ══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}[2/3] SIFT Workstation VM${NC}"

if vmrun list 2>/dev/null | grep -q "SIFT.vmx"; then
    echo "  Sending shutdown signal..."
    vmrun -T ws stop "$SIFT_VMX" soft 2>/dev/null || true
    # Wait up to 30s for graceful shutdown
    STOPPED=false
    for i in $(seq 1 15); do
        vmrun list 2>/dev/null | grep -q "SIFT.vmx" || { STOPPED=true; break; }
        sleep 2
    done
    if $STOPPED; then
        echo -e "  ${GREEN}✓${NC} VM stopped gracefully"
    else
        echo -e "  ${YELLOW}⚠${NC}  VM didn't stop — forcing..."
        vmrun -T ws stop "$SIFT_VMX" hard 2>/dev/null || true
        sleep 3
        if vmrun list 2>/dev/null | grep -q "SIFT.vmx"; then
            echo -e "  ${RED}✗${NC} VM still running — manual intervention needed"
        else
            echo -e "  ${GREEN}✓${NC} VM force-stopped"
        fi
    fi
else
    echo "  (VM not running)"
fi

# ══════════════════════════════════════════════════════════════════════════
# Step 3: Lock LUKS Volume
# ══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}[3/3] LUKS Evidence Volume${NC}"

if mountpoint -q "$FORENSICS_DIR" 2>/dev/null; then
    echo "  Unmounting $FORENSICS_DIR..."
    if sudo -n umount "$FORENSICS_DIR" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Unmounted"
    else
        echo -e "  ${RED}✗${NC} Unmount failed — filesystem busy?"
        echo "  Check: lsof $FORENSICS_DIR"
    fi
fi

if sudo cryptsetup status "$LUKS_NAME" >/dev/null 2>&1; then
    echo "  Locking LUKS volume..."
    if sudo -n cryptsetup close "$LUKS_NAME" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} LUKS locked"
    else
        echo -e "  ${RED}✗${NC} LUKS close failed"
    fi
else
    echo "  (LUKS not open)"
fi

# ══════════════════════════════════════════════════════════════════════════
# Final
# ══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✓ FORENSICS SYSTEM SHUT DOWN               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
