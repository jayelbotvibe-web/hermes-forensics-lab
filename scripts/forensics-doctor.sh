#!/bin/bash
# ============================================================================
# forensics-doctor.sh — Diagnose the lab and tell you exactly how to fix it.
#
# Every check answers three questions: what is required, whether you have it,
# and the exact command that fixes it. Nothing here modifies your system.
#
# Usage:
#   bash scripts/forensics-doctor.sh            # full report
#   bash scripts/forensics-doctor.sh --quiet    # only problems
#   bash scripts/forensics-doctor.sh --config   # resolved config, then exit
#
# Exit codes:  0 = ready   1 = degraded (usable)   2 = blocked (cannot run)
# ============================================================================
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

QUIET=false
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet|-q) QUIET=true; shift ;;
        --config)   echo -e "${CYAN}${BOLD}Resolved configuration${NC}"
                    forensics_print_config; exit 0 ;;
        -h|--help)  sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          die "unknown argument: $1 (try --help)" ;;
    esac
done

BLOCKERS=()   # cannot run the lab at all
GAPS=()       # runs, but degraded

# check <label> <status> [fix-hint]
#   status: ok | gap | blocker | skip
check() {
    local label="$1" status="$2" fix="${3:-}"
    case "$status" in
        ok)      $QUIET || log_ok "$label" ;;
        skip)    $QUIET || log_info "$label" ;;
        gap)     log_warn "$label"
                 [ -n "$fix" ] && echo -e "      ${DIM}fix:${NC} $fix"
                 GAPS+=("$label") ;;
        blocker) log_err "$label"
                 [ -n "$fix" ] && echo -e "      ${DIM}fix:${NC} $fix"
                 BLOCKERS+=("$label") ;;
    esac
}

echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║   Hermes Forensics — Environment Doctor        ║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════╝${NC}"

# ── Configuration ──────────────────────────────────────────────────────────

log_step "Configuration"
if [ -n "${FORENSICS_CONF_LOADED:-}" ]; then
    check "Config file: $FORENSICS_CONF_LOADED" ok
else
    check "No config file — using built-in defaults" gap \
        "cp forensics.conf.example \"\${XDG_CONFIG_HOME:-\$HOME/.config}\"/hermes-forensics/forensics.conf"
fi
$QUIET || { echo ""; forensics_print_config; }

# ── Host prerequisites ─────────────────────────────────────────────────────

log_step "Host prerequisites"

if [ "$(uname -s)" = "Linux" ]; then
    check "Linux host" ok
else
    check "Host is $(uname -s) — the lab requires Linux (cryptsetup, FUSE, vmrun)" blocker \
        "Run the lab inside a Linux VM, or use the standalone tools only (see README)"
fi

for tool in bash python3 docker ssh; do
    if command -v "$tool" >/dev/null 2>&1; then
        check "$tool" ok
    else
        case "$tool" in
            docker) check "docker — not installed" blocker \
                        "https://docs.docker.com/engine/install/  (the 3 tool images need it)" ;;
            *)      check "$tool — not installed" blocker "sudo apt install $tool" ;;
        esac
    fi
done

if command -v python3 >/dev/null 2>&1; then
    PYV="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)"
    if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)' 2>/dev/null; then
        check "Python $PYV (>= 3.8)" ok
    else
        check "Python $PYV is too old — need >= 3.8" blocker "sudo apt install python3"
    fi
fi

if is_enabled "$FORENSICS_VAULT_ENABLED"; then
    if command -v cryptsetup >/dev/null 2>&1; then
        check "cryptsetup" ok
    else
        check "cryptsetup — required by the encrypted vault" blocker \
            "sudo apt install cryptsetup   (or set FORENSICS_VAULT_ENABLED=false)"
    fi
fi

# ── Python packages ────────────────────────────────────────────────────────

log_step "Python packages (report generation)"
MISSING_PY=()
for mod in jinja2 weasyprint markitdown; do
    if python3 -c "import $mod" >/dev/null 2>&1; then
        check "$mod" ok
    else
        MISSING_PY+=("$mod")
    fi
done
if [ ${#MISSING_PY[@]} -gt 0 ]; then
    check "Missing: ${MISSING_PY[*]} — HTML/PDF reports will fail" gap \
        "pip install -r requirements.txt   (weasyprint also needs: sudo apt install libpango-1.0-0 libcairo2 libgdk-pixbuf-2.0-0)"
fi

# ── Docker ─────────────────────────────────────────────────────────────────

log_step "Docker runtime and images"
if docker info >/dev/null 2>&1; then
    check "Docker daemon reachable" ok
    for img in "$IMAGE_VOLATILITY3" "$IMAGE_PLASO" "$IMAGE_MFT_TOOLS"; do
        if docker image inspect "$img" >/dev/null 2>&1; then
            check "$img" ok
        else
            check "$img — not built" gap "make images   (or: ./install.sh --images-only)"
        fi
    done
elif command -v docker >/dev/null 2>&1; then
    check "Docker installed but daemon unreachable" blocker \
        "sudo systemctl start docker   (and: sudo usermod -aG docker \$USER, then log out and back in)"
fi

# ── Evidence vault ─────────────────────────────────────────────────────────

log_step "Evidence vault"
if ! is_enabled "$FORENSICS_VAULT_ENABLED"; then
    check "Vault disabled — evidence stored unencrypted at $FORENSICS_HOME" skip
    if [ -d "$FORENSICS_HOME" ]; then
        check "$FORENSICS_HOME exists" ok
    else
        check "$FORENSICS_HOME does not exist" gap "mkdir -p $FORENSICS_HOME/{cases,tools,scripts,fixtures,logs}"
    fi
elif mountpoint -q "$FORENSICS_HOME" 2>/dev/null; then
    check "Vault mounted at $FORENSICS_HOME ($(df -h "$FORENSICS_HOME" 2>/dev/null | tail -1 | awk '{print $4}') free)" ok
elif [ -f "$FORENSICS_IMG" ]; then
    check "Vault exists but is not mounted" gap "bash scripts/forensics-up.sh"
else
    check "No evidence vault at $FORENSICS_IMG" blocker \
        "bash scripts/create-evidence-vault.sh --size 60G"
fi

if is_enabled "$FORENSICS_VAULT_ENABLED" && [ -f "$FORENSICS_IMG" ]; then
    if [ -f "$FORENSICS_KEYFILE" ]; then
        PERMS="$(stat -c '%a' "$FORENSICS_KEYFILE" 2>/dev/null)"
        if [ "$PERMS" = "600" ]; then
            check "Keyfile present (0600)" ok
        else
            check "Keyfile is mode $PERMS — should be 0600" gap "chmod 600 $FORENSICS_KEYFILE"
        fi
    else
        check "No keyfile — bring-up will prompt for the passphrase" skip
    fi
fi

# Lab skeleton
if [ -d "$FORENSICS_HOME" ]; then
    MISSING_DIRS=()
    for d in cases tools scripts fixtures logs; do
        [ -d "$FORENSICS_HOME/$d" ] || MISSING_DIRS+=("$d")
    done
    if [ ${#MISSING_DIRS[@]} -eq 0 ]; then
        check "Lab skeleton complete" ok
    else
        check "Missing directories: ${MISSING_DIRS[*]}" gap \
            "mkdir -p $FORENSICS_HOME/{cases,tools,scripts,fixtures,logs}"
    fi
fi

# ── MemProcFS ──────────────────────────────────────────────────────────────

log_step "MemProcFS (host memory forensics)"
if [ -x "$MEMPROCFS_BIN" ]; then
    MPF_VER="$(timeout 10 "$MEMPROCFS_BIN" -version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [ "$MPF_VER" = "$MEMPROCFS_EXPECTED_VERSION" ]; then
        check "MemProcFS v$MPF_VER" ok
    elif [ -n "$MPF_VER" ]; then
        check "MemProcFS v$MPF_VER installed, catalog pins v$MEMPROCFS_EXPECTED_VERSION" gap \
            "Either reinstall the pinned version or set MEMPROCFS_EXPECTED_VERSION=$MPF_VER"
    else
        check "MemProcFS present but version unreadable" gap "Check that libfuse2t64 is installed"
    fi
    if ldconfig -p 2>/dev/null | grep -q libfuse2 || [ -e /dev/fuse ]; then
        check "FUSE available" ok
    else
        check "FUSE missing — MemProcFS cannot mount" gap "sudo apt install libfuse2t64"
    fi
else
    check "MemProcFS not found at $MEMPROCFS_BIN" gap "./install.sh --memprocfs-only"
fi

# ── SIFT VM ────────────────────────────────────────────────────────────────

log_step "SIFT Workstation VM"
if ! is_enabled "$SIFT_ENABLED"; then
    check "SIFT disabled — host-only mode, 8 filesystem tools unavailable" skip
elif [ -z "$SIFT_HOST" ]; then
    check "SIFT_HOST not set — 8 filesystem tools unavailable" gap \
        "bash scripts/provision-sift.sh <vm-ip>   (or set SIFT_ENABLED=false for host-only)"
else
    # shellcheck disable=SC2046
    if ssh $(sift_ssh_opts | tr '\n' ' ') "$SIFT_USER@$SIFT_HOST" true 2>/dev/null; then
        check "SSH to $SIFT_USER@$SIFT_HOST" ok
        TOOLS_MISSING=()
        for entry in "sleuthkit:fls" "foremost:foremost" "photorec:photorec" \
                     "dc3dd:dc3dd" "ddrescue:ddrescue" "regripper:/usr/lib/regripper/rip.pl" \
                     "hashdeep:hashdeep" "tshark:tshark"; do
            name="${entry%%:*}"; probe="${entry#*:}"
            # shellcheck disable=SC2046
            ssh $(sift_ssh_opts | tr '\n' ' ') "$SIFT_USER@$SIFT_HOST" \
                "command -v $probe >/dev/null 2>&1 || [ -f $probe ]" 2>/dev/null \
                || TOOLS_MISSING+=("$name")
        done
        if [ ${#TOOLS_MISSING[@]} -eq 0 ]; then
            check "All 8 SIFT tools present" ok
        else
            check "SIFT tools missing: ${TOOLS_MISSING[*]}" gap \
                "bash scripts/provision-sift.sh $SIFT_HOST"
        fi
    else
        check "Cannot SSH to $SIFT_USER@$SIFT_HOST" gap \
            "Start the VM, then: bash scripts/provision-sift.sh $SIFT_HOST"
    fi
fi

if [ -n "$SIFT_VMX" ]; then
    if command -v vmrun >/dev/null 2>&1; then
        check "vmrun available (VM auto start/stop enabled)" ok
        [ -f "$SIFT_VMX" ] || check "SIFT_VMX points at a missing file: $SIFT_VMX" gap \
            "Correct SIFT_VMX in your forensics.conf"
    else
        check "SIFT_VMX set but vmrun not on PATH" gap \
            "Add VMware to PATH, or clear SIFT_VMX and start the VM yourself"
    fi
else
    check "SIFT_VMX unset — start/stop the VM yourself" skip
fi

# ── Hermes agent ───────────────────────────────────────────────────────────

log_step "Hermes agent (optional)"
if command -v hermes >/dev/null 2>&1; then
    check "hermes on PATH" ok
    if [ -f "$HERMES_PROFILE_DIR/config.yaml" ]; then
        check "Forensics profile installed" ok
    else
        check "Profile not installed at $HERMES_PROFILE_DIR" gap "./install.sh --profile-only"
    fi
else
    check "hermes not installed — scripts and encyclopedia still work without it" skip
fi

# ── Verdict ────────────────────────────────────────────────────────────────

echo ""
if [ ${#BLOCKERS[@]} -eq 0 ] && [ ${#GAPS[@]} -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ Lab ready.${NC}  Start with: bash scripts/forensics-up.sh"
    echo ""
    exit 0
fi

if [ ${#BLOCKERS[@]} -gt 0 ]; then
    echo -e "${RED}${BOLD}✗ Blocked${NC} — ${#BLOCKERS[@]} problem(s) prevent the lab from running:"
    printf '    %s\n' "${BLOCKERS[@]}"
fi
if [ ${#GAPS[@]} -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}⚠ Degraded${NC} — ${#GAPS[@]} gap(s); the lab runs with reduced capability:"
    printf '    %s\n' "${GAPS[@]}"
fi
echo ""
echo -e "  ${DIM}Most gaps are fixed by:${NC} ./install.sh"
echo ""
[ ${#BLOCKERS[@]} -gt 0 ] && exit 2
exit 1
