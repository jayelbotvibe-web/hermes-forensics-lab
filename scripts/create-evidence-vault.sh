#!/bin/bash
# ============================================================================
# create-evidence-vault.sh — Create the LUKS-encrypted evidence container.
#
# forensics-up.sh requires an encrypted vault to exist before it will run.
# Nothing else in the lab creates one. This script does.
#
# Usage:
#   bash scripts/create-evidence-vault.sh                 # 40G, prompts for passphrase
#   bash scripts/create-evidence-vault.sh --size 100G
#   bash scripts/create-evidence-vault.sh --no-keyfile    # passphrase every time
#
# What it produces:
#   $FORENSICS_IMG          sparse LUKS2 container file
#   $FORENSICS_KEYFILE      0600 keyfile so bring-up is non-interactive
#   $FORENSICS_HOME         mountpoint, owned by you, with the lab skeleton
#
# Safety: refuses to touch an existing container. To start over you must
# delete the image yourself — this script will never destroy evidence.
# ============================================================================
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

SIZE="40G"
USE_KEYFILE=true

usage() {
    sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --size)       SIZE="${2:-}"; shift 2 ;;
        --size=*)     SIZE="${1#*=}"; shift ;;
        --no-keyfile) USE_KEYFILE=false; shift ;;
        -h|--help)    usage ;;
        *)            die "unknown argument: $1 (try --help)" ;;
    esac
done

[ -n "$SIZE" ] || die "--size requires a value (e.g. 60G)"

echo -e "${CYAN}${BOLD}Hermes Forensics — Evidence Vault Setup${NC}"
echo ""
echo "  Container:  $FORENSICS_IMG"
echo "  Size:       $SIZE"
echo "  Mountpoint: $FORENSICS_HOME"
echo "  Keyfile:    $($USE_KEYFILE && echo "$FORENSICS_KEYFILE" || echo "none — passphrase on every mount")"
echo ""

# ── Preconditions ──────────────────────────────────────────────────────────

command -v cryptsetup >/dev/null 2>&1 || die \
    "cryptsetup not installed. Install it with:
    Debian/Ubuntu:  sudo apt install cryptsetup
    Fedora/RHEL:    sudo dnf install cryptsetup
    Arch:           sudo pacman -S cryptsetup"

if [ -e "$FORENSICS_IMG" ]; then
    log_err "A container already exists at $FORENSICS_IMG"
    echo ""
    echo "  This script will not overwrite it — it may hold evidence."
    echo "  To mount it:        bash scripts/forensics-up.sh"
    echo "  To start over:      rm $FORENSICS_IMG   (destroys its contents)"
    exit 1
fi

if mountpoint -q "$FORENSICS_HOME" 2>/dev/null; then
    die "$FORENSICS_HOME is already a mountpoint. Unmount it first: sudo umount $FORENSICS_HOME"
fi

if [ -d "$FORENSICS_HOME" ] && [ -n "$(ls -A "$FORENSICS_HOME" 2>/dev/null)" ]; then
    log_warn "$FORENSICS_HOME already exists and is not empty."
    echo "  Mounting the vault there will HIDE its current contents until unmounted."
    echo "  Existing entries:"
    ls -A "$FORENSICS_HOME" | head -5 | sed 's/^/    /'
    echo ""
    read -r -p "  Continue anyway? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "  Aborted."; exit 1; }
fi

# Confirm before we start asking for sudo and passphrases.
echo "  This needs sudo (losetup, cryptsetup, mount)."
read -r -p "  Create the vault now? [Y/n] " reply
[[ -z "$reply" || "$reply" =~ ^[Yy]$ ]] || { echo "  Aborted."; exit 1; }

# ── Cleanup on failure ─────────────────────────────────────────────────────
# A half-created vault is worse than none. Unwind whatever we managed to do.
LOOP_DEV=""
CLEANUP_LUKS=false
cleanup_on_error() {
    local rc=$?
    [ $rc -eq 0 ] && return 0
    echo ""
    log_warn "Setup failed — rolling back."
    $CLEANUP_LUKS && sudo cryptsetup close "$FORENSICS_LUKS_NAME" 2>/dev/null
    [ -n "$LOOP_DEV" ] && sudo losetup -d "$LOOP_DEV" 2>/dev/null
    [ -e "$FORENSICS_IMG" ] && rm -f "$FORENSICS_IMG"
    log_info "Rolled back. Nothing was left behind."
    exit $rc
}
trap cleanup_on_error EXIT

# ── 1. Allocate the container ──────────────────────────────────────────────

log_step "[1/6] Allocating container"
# Sparse — consumes disk only as evidence is written into it.
truncate -s "$SIZE" "$FORENSICS_IMG" || die "could not allocate $SIZE at $FORENSICS_IMG"
chmod 600 "$FORENSICS_IMG"
log_ok "Created $FORENSICS_IMG (sparse, $SIZE)"

# ── 2. Format as LUKS2 ─────────────────────────────────────────────────────

log_step "[2/6] Formatting as LUKS2"
echo -e "  ${BOLD}Choose a strong passphrase.${NC} This encrypts your evidence at rest."
echo -e "  ${DIM}There is no recovery if you lose it.${NC}"
echo ""
sudo cryptsetup luksFormat --type luks2 --batch-mode --verify-passphrase "$FORENSICS_IMG" \
    || die "luksFormat failed"
log_ok "LUKS2 header written"

# ── 3. Optional keyfile ────────────────────────────────────────────────────

if $USE_KEYFILE; then
    log_step "[3/6] Adding keyfile for unattended mount"
    if [ -e "$FORENSICS_KEYFILE" ]; then
        log_warn "Keyfile already exists at $FORENSICS_KEYFILE — reusing it"
    else
        # Random binary keyfile, not a stored passphrase. Sits at 0600 in $HOME;
        # protects against casual disk theft, not against a compromised account.
        ( umask 077; head -c 4096 /dev/urandom > "$FORENSICS_KEYFILE" )
        chmod 600 "$FORENSICS_KEYFILE"
        log_ok "Generated 4096-byte random keyfile"
    fi
    echo "  Enter the passphrase you just chose, to authorise the keyfile:"
    sudo cryptsetup luksAddKey "$FORENSICS_IMG" "$FORENSICS_KEYFILE" \
        || die "luksAddKey failed — the vault exists but has no keyfile.
    Re-run: sudo cryptsetup luksAddKey $FORENSICS_IMG $FORENSICS_KEYFILE"
    log_ok "Keyfile enrolled — bring-up will not prompt"
else
    log_step "[3/6] Skipping keyfile (--no-keyfile)"
    log_info "forensics-up.sh will prompt for the passphrase each time"
fi

# ── 4. Open and make a filesystem ──────────────────────────────────────────

log_step "[4/6] Creating filesystem"
if $USE_KEYFILE; then
    sudo cryptsetup open "$FORENSICS_IMG" "$FORENSICS_LUKS_NAME" --key-file="$FORENSICS_KEYFILE" \
        || die "could not open the container with the keyfile"
else
    sudo cryptsetup open "$FORENSICS_IMG" "$FORENSICS_LUKS_NAME" \
        || die "could not open the container"
fi
CLEANUP_LUKS=true

sudo mkfs.ext4 -q -L forensics "/dev/mapper/$FORENSICS_LUKS_NAME" \
    || die "mkfs.ext4 failed"
log_ok "ext4 filesystem created"

# ── 5. Mount and hand over ownership ───────────────────────────────────────

log_step "[5/6] Mounting"
sudo mkdir -p "$FORENSICS_HOME"
sudo mount "/dev/mapper/$FORENSICS_LUKS_NAME" "$FORENSICS_HOME" || die "mount failed"
sudo chown "$(id -u):$(id -g)" "$FORENSICS_HOME"
log_ok "Mounted at $FORENSICS_HOME"

# ── 6. Lab skeleton ────────────────────────────────────────────────────────
# The canary checks for these five directories by name.

log_step "[6/6] Creating lab skeleton"
mkdir -p "$FORENSICS_HOME"/{cases,tools,scripts,fixtures,logs}
log_ok "cases/ tools/ scripts/ fixtures/ logs/"

trap - EXIT

echo ""
echo -e "${GREEN}${BOLD}✓ Evidence vault ready.${NC}"
echo ""
echo "  Mounted:  $FORENSICS_HOME  ($(df -h "$FORENSICS_HOME" | tail -1 | awk '{print $4}') available)"
echo ""
echo "  Next:     bash scripts/forensics-doctor.sh   # check the rest of the lab"
echo "  Daily:    bash scripts/forensics-up.sh       # mount + start VM + canary"
echo "            bash scripts/forensics-down.sh     # unmount + stop VM"
echo ""
if $USE_KEYFILE; then
    echo -e "  ${YELLOW}Note:${NC} $FORENSICS_KEYFILE unlocks this vault. Back it up somewhere"
    echo "  safe, and remember it is only as protected as your user account."
    echo ""
fi
