#!/bin/bash
# ============================================================================
# provision-sift.sh — Install the forensic toolchain on the SIFT VM.
#
# Replaces the manual apt/ssh-copy-id steps. Run from the HOST,
# against a freshly installed Ubuntu 22.04 VM that has OpenSSH running.
#
# Usage:
#   bash scripts/provision-sift.sh 192.168.1.50
#   bash scripts/provision-sift.sh 192.168.1.50 --user analyst
#   bash scripts/provision-sift.sh --check          # verify an existing VM
#
# What it does:
#   1. Installs your SSH key on the VM (prompts for password once)
#   2. apt-installs the eight SIFT-native tools the canary checks for
#   3. Sets up the sshfs mount so the VM sees your cases read-only
#   4. Writes SIFT_HOST/SIFT_USER back into your forensics.conf
#   5. Re-runs the tool probe to confirm all eight are present
# ============================================================================
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CHECK_ONLY=false
TARGET_HOST=""
TARGET_USER="$SIFT_USER"

usage() {
    sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check)   CHECK_ONLY=true; shift ;;
        --user)    TARGET_USER="${2:-}"; shift 2 ;;
        --user=*)  TARGET_USER="${1#*=}"; shift ;;
        -h|--help) usage ;;
        -*)        die "unknown argument: $1 (try --help)" ;;
        *)         TARGET_HOST="$1"; shift ;;
    esac
done

[ -n "$TARGET_HOST" ] || TARGET_HOST="$SIFT_HOST"
[ -n "$TARGET_HOST" ] || die "no VM address given.
    Usage: bash scripts/provision-sift.sh <ip-or-hostname>
    Find it by running 'ip -4 addr' inside the VM."
[ -n "$TARGET_USER" ] || die "--user cannot be empty"

# The eight tools session-canary.sh probes for, plus their apt packages.
APT_PACKAGES=(
    sleuthkit foremost testdisk dc3dd gddrescue hashdeep tshark
    ewf-tools afflib-tools regripper python3-pip sshfs
)
# name:probe — must stay in sync with session-canary.sh SIFT_TOOLS.
PROBES=(
    "sleuthkit:fls" "foremost:foremost" "photorec:photorec"
    "dc3dd:dc3dd" "ddrescue:ddrescue" "regripper:/usr/lib/regripper/rip.pl"
    "hashdeep:hashdeep" "tshark:tshark"
)

ssh_to_vm() {
    # shellcheck disable=SC2046
    ssh $(sift_ssh_opts | tr '\n' ' ') "$TARGET_USER@$TARGET_HOST" "$@"
}

probe_tools() {
    local missing=() found=0 name probe
    for entry in "${PROBES[@]}"; do
        name="${entry%%:*}"; probe="${entry#*:}"
        if ssh_to_vm "command -v $probe >/dev/null 2>&1 || [ -f $probe ]" 2>/dev/null; then
            log_ok "$name"
            found=$((found + 1))
        else
            log_err "$name — not found"
            missing+=("$name")
        fi
    done
    echo ""
    if [ ${#missing[@]} -eq 0 ]; then
        echo -e "  ${GREEN}All ${found}/8 SIFT tools present.${NC}"
        return 0
    fi
    echo -e "  ${YELLOW}${found}/8 present — missing: ${missing[*]}${NC}"
    return 1
}

echo -e "${CYAN}${BOLD}Hermes Forensics — SIFT VM Provisioning${NC}"
echo ""
echo "  Target: $TARGET_USER@$TARGET_HOST"
echo ""

# ── Check-only mode ────────────────────────────────────────────────────────

if $CHECK_ONLY; then
    log_step "Probing tools"
    if ! ssh_to_vm true 2>/dev/null; then
        die "cannot reach $TARGET_USER@$TARGET_HOST over SSH.
    Is the VM running?      vmrun list
    Is the address right?   ping $TARGET_HOST
    Is your key installed?  ssh-copy-id $TARGET_USER@$TARGET_HOST"
    fi
    probe_tools
    exit $?
fi

# ── 1. Reachability ────────────────────────────────────────────────────────

log_step "[1/5] Reaching the VM"
if ! ping -c1 -W3 "$TARGET_HOST" >/dev/null 2>&1; then
    log_warn "$TARGET_HOST does not answer ping (may just be firewalled — continuing)"
else
    log_ok "$TARGET_HOST is up"
fi

# ── 2. SSH key ─────────────────────────────────────────────────────────────

log_step "[2/5] SSH key authentication"
if ssh_to_vm true 2>/dev/null; then
    log_ok "Key auth already working"
else
    if [ ! -f "$SSH_IDENTITY" ]; then
        log_info "No key at $SSH_IDENTITY — generating one"
        ssh-keygen -t ed25519 -f "$SSH_IDENTITY" -N "" -C "hermes-forensics" \
            || die "ssh-keygen failed"
        log_ok "Generated $SSH_IDENTITY"
    fi
    echo "  Installing your public key on the VM. Enter the VM password when asked:"
    ssh-copy-id -i "${SSH_IDENTITY}.pub" "$TARGET_USER@$TARGET_HOST" \
        || die "ssh-copy-id failed. Check the username and that the VM allows password auth."
    ssh_to_vm true 2>/dev/null \
        || die "key installed but authentication still fails — check VM sshd config"
    log_ok "Key auth working"
fi

# ── 3. Forensic tools ──────────────────────────────────────────────────────

log_step "[3/5] Installing forensic tools (this takes a few minutes)"
log_info "${#APT_PACKAGES[@]} apt packages"
if ssh_to_vm "sudo -n true" 2>/dev/null; then
    SUDO_PREFIX="sudo -n"
else
    echo "  The VM will prompt for its sudo password."
    SUDO_PREFIX="sudo"
fi

# DEBIAN_FRONTEND must be set *inside* the sudo environment via `env`. Setting
# it before `sudo` does nothing: sudo resets the environment by default
# (env_reset), so the variable never reaches apt and packages that ask debconf
# questions — tshark's "allow non-superusers to capture?" among them — block
# forever on a prompt nobody can see.
#
# -t so sudo can prompt interactively if passwordless sudo is not configured.
# shellcheck disable=SC2046
ssh -t $(sift_ssh_opts interactive | tr '\n' ' ') "$TARGET_USER@$TARGET_HOST" \
    "$SUDO_PREFIX env DEBIAN_FRONTEND=noninteractive apt-get update -qq && \
     $SUDO_PREFIX env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ${APT_PACKAGES[*]} && \
     pip3 install --quiet python-registry" \
    || log_warn "apt install reported errors — the probe below will show what is missing"

# ── 4. Evidence mount ──────────────────────────────────────────────────────

log_step "[4/5] Evidence mount (sshfs)"
HOST_IP="$(ip -4 route get "$TARGET_HOST" 2>/dev/null | grep -oP 'src \K\S+' | head -1)"
if [ -z "$HOST_IP" ]; then
    log_warn "Could not determine this host's IP on the VM's network — skipping"
    log_info "Set it up manually on the VM, see INSTALL.md"
else
    log_info "This host is $HOST_IP from the VM's perspective"
    # Read-only: the VM analyses evidence, it never writes to the vault.
    ssh_to_vm "mkdir -p ~/cases && \
        grep -q '$HOST_IP:$FORENSICS_HOME/cases' ~/.sshfs-forensics 2>/dev/null || \
        echo 'sshfs $USER@$HOST_IP:$FORENSICS_HOME/cases ~/cases -o ro,reconnect,ServerAliveInterval=15' \
            > ~/.sshfs-forensics" 2>/dev/null \
        && log_ok "Wrote ~/.sshfs-forensics on the VM" \
        || log_warn "Could not write the mount helper"
    log_info "The VM needs your host SSH key to mount. To finish, on the VM run:"
    echo "      ssh-copy-id $USER@$HOST_IP && bash ~/.sshfs-forensics"
fi

# ── 5. Verify and persist ──────────────────────────────────────────────────

log_step "[5/5] Verifying toolchain"
PROBE_RC=0
probe_tools || PROBE_RC=1

CFG="$(forensics_config_path 2>/dev/null || true)"
if [ -n "$CFG" ] && [ -f "$CFG" ]; then
    if grep -q "^SIFT_HOST=" "$CFG"; then
        sed -i "s|^SIFT_HOST=.*|SIFT_HOST=\"$TARGET_HOST\"|" "$CFG"
    else
        echo "SIFT_HOST=\"$TARGET_HOST\"" >> "$CFG"
    fi
    if grep -q "^SIFT_USER=" "$CFG"; then
        sed -i "s|^SIFT_USER=.*|SIFT_USER=\"$TARGET_USER\"|" "$CFG"
    else
        echo "SIFT_USER=\"$TARGET_USER\"" >> "$CFG"
    fi
    log_ok "Saved SIFT_HOST/SIFT_USER to $CFG"
else
    log_warn "No config file found — add these yourself:"
    echo "      SIFT_HOST=\"$TARGET_HOST\""
    echo "      SIFT_USER=\"$TARGET_USER\""
fi

echo ""
if [ $PROBE_RC -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ SIFT VM provisioned.${NC}"
else
    echo -e "${YELLOW}${BOLD}⚠ SIFT VM provisioned with gaps.${NC}"
    echo "  Re-run with --check after fixing, or install the missing packages by hand."
fi
echo ""
echo "  Next: bash scripts/forensics-doctor.sh"
echo ""
exit $PROBE_RC
