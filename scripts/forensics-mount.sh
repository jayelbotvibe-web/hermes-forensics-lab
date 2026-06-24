#!/bin/bash
# ============================================================================
# forensics-mount.sh — MemProcFS mount with stale-mount cleanup.
#
# Usage:  bash forensics-mount.sh CASE_ID
#         bash forensics-mount.sh --unmount
#
# Mounts the first .mem file in the case evidence directory via MemProcFS.
# Auto-cleans stale mounts. After mounting, browse at /home/niel/forensics/mounts/mem/
# ============================================================================
set -uo pipefail

ACTION="${1:-}"
MEMPROCFS="/home/niel/memprocfs/memprocfs"
MOUNT_POINT="/home/niel/forensics/mounts/mem"
FORENSICS_DIR="/home/niel/forensics"

# ── Unmount mode ──────────────────────────────────────────────────────────

if [ "$ACTION" = "--unmount" ] || [ "$ACTION" = "-u" ]; then
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        fusermount -u "$MOUNT_POINT" 2>/dev/null && echo "Unmounted $MOUNT_POINT" || {
            echo "Unmount failed — force-unmounting..."
            fusermount -uz "$MOUNT_POINT" 2>/dev/null
            echo "Force-unmounted"
        }
    else
        echo "(not mounted)"
    fi
    exit 0
fi

# ── Mount mode ────────────────────────────────────────────────────────────

CASE_ID="${ACTION:?Usage: forensics-mount.sh CASE_ID | forensics-mount.sh --unmount}"
CASE_DIR="$FORENSICS_DIR/cases/$CASE_ID"
EVIDENCE_DIR="$CASE_DIR/evidence"

if [ ! -d "$CASE_DIR" ]; then
    echo "ERROR: Case directory not found: $CASE_DIR" >&2
    exit 1
fi

MEM_FILE=$(ls "$EVIDENCE_DIR"/*.mem "$EVIDENCE_DIR"/*.dmp "$EVIDENCE_DIR"/*.raw "$EVIDENCE_DIR"/*.vmem 2>/dev/null | head -1)
if [ -z "$MEM_FILE" ]; then
    echo "ERROR: No memory dump found in $EVIDENCE_DIR" >&2
    exit 1
fi

# Clean up stale mounts
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "Unmounting stale mount..."
    fusermount -uz "$MOUNT_POINT" 2>/dev/null || true
    sleep 1
fi

# Clean stale dir (leftover from previous failed mount)
if [ -d "$MOUNT_POINT" ] && ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    rmdir "$MOUNT_POINT" 2>/dev/null || rm -rf "$MOUNT_POINT" 2>/dev/null
fi

mkdir -p "$MOUNT_POINT"

echo "=== MemProcFS ==="
echo "  Case: $CASE_ID"
echo "  Dump: $(basename "$MEM_FILE")"
echo "  Mount: $MOUNT_POINT"
echo ""

echo "Mounting (forensic mode, ~25s for 5GB dump)..."
"$MEMPROCFS" -device "$MEM_FILE" -mount "$MOUNT_POINT" -forensic 1 2>&1 || {
    echo ""
    echo "Mount failed. Check:"
    echo "  1. Is libfuse2 installed? (sudo apt install libfuse2t64)"
    echo "  2. Is the dump file readable?"
    echo "  3. Run: fusermount -uz $MOUNT_POINT"
    exit 1
}

echo ""
echo "  ✓ Mounted at $MOUNT_POINT"
echo ""
echo "  Key paths:"
echo "    Processes:  $MOUNT_POINT/sys/proc/"
echo "    Network:    $MOUNT_POINT/sys/net/tcp.txt"
echo "    Malware:    $MOUNT_POINT/forensic/findevil.txt"
echo ""
echo "  Unmount: bash forensics-mount.sh --unmount"
