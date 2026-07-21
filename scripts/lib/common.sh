#!/bin/bash
# ============================================================================
# common.sh — shared configuration loader and helpers.
#
# Source this at the top of every lab script:
#
#     source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# Resolution order for every setting (first wins):
#   1. Environment variable already set in the caller's shell
#   2. The config file (see forensics_config_path below)
#   3. The built-in default in this file
#
# This file sets no 'set -e' / 'set -u' of its own — the sourcing script owns
# its shell options.
# ============================================================================

# Guard against double-sourcing (scripts call each other).
[ -n "${_FORENSICS_COMMON_LOADED:-}" ] && return 0
_FORENSICS_COMMON_LOADED=1

# ── Colors ─────────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; DIM=''; BOLD=''; NC=''
fi
export RED GREEN YELLOW CYAN DIM BOLD NC

# ── Logging helpers ────────────────────────────────────────────────────────
log_ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
log_warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
log_err()  { echo -e "  ${RED}✗${NC} $*"; }
log_info() { echo -e "  ${DIM}·${NC} $*"; }
log_step() { echo -e "\n${CYAN}${BOLD}$*${NC}"; }
die()      { echo -e "${RED}error:${NC} $*" >&2; exit 1; }

# ── Identity ───────────────────────────────────────────────────────────────
# $USER is not set in containers, cron, or `su` without a login shell. Scripts
# here run under `set -u`, so an unset $USER aborts them outright.
: "${USER:=$(id -un)}"
export USER

# ── Repo root ──────────────────────────────────────────────────────────────
# lib/ lives under scripts/, so the repo root is two levels up.
FORENSICS_REPO="${FORENSICS_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export FORENSICS_REPO

# ── Locate the config file ─────────────────────────────────────────────────
forensics_config_path() {
    if [ -n "${FORENSICS_CONF:-}" ]; then
        echo "$FORENSICS_CONF"; return 0
    fi
    local xdg="${XDG_CONFIG_HOME:-$HOME/.config}/hermes-forensics/forensics.conf"
    if [ -f "$xdg" ]; then echo "$xdg"; return 0; fi
    if [ -f "$FORENSICS_REPO/forensics.conf" ]; then
        echo "$FORENSICS_REPO/forensics.conf"; return 0
    fi
    return 1
}

# ── Load the config file ───────────────────────────────────────────────────
# Only plain `KEY=value` assignments are honoured. Anything that could execute
# (command substitution, pipes, semicolons, backticks) is refused outright —
# a config file is data, and this one may be shared between analysts.
forensics_load_config() {
    local cfg
    cfg="$(forensics_config_path)" || return 0
    FORENSICS_CONF_LOADED="$cfg"; export FORENSICS_CONF_LOADED

    local line key val lineno=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        # Strip comments and surrounding whitespace.
        line="${line%%#*}"
        line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -z "$line" ] && continue

        if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            echo "warning: $cfg:$lineno — not an assignment, ignored" >&2
            continue
        fi
        key="${line%%=*}"
        val="${line#*=}"

        if [[ "$val" == *'$('* || "$val" == *'`'* || "$val" == *';'* || "$val" == *'|'* || "$val" == *'&'* ]]; then
            echo "warning: $cfg:$lineno — $key contains shell metacharacters, ignored" >&2
            continue
        fi

        # Environment always wins over the file.
        [ -n "${!key:-}" ] && continue

        # Strip one layer of quotes, then expand $HOME and friends.
        val="${val%\"}"; val="${val#\"}"
        val="${val%\'}"; val="${val#\'}"
        eval "$key=\"$val\""
        export "${key?}"
    done < "$cfg"
}

forensics_load_config

# ── Defaults ───────────────────────────────────────────────────────────────
# Applied only where neither the environment nor the config file spoke.
: "${FORENSICS_HOME:=$HOME/forensics}"

: "${FORENSICS_VAULT_ENABLED:=true}"
: "${FORENSICS_IMG:=$HOME/forensics.img}"
: "${FORENSICS_KEYFILE:=$HOME/.forensics-keyfile}"
: "${FORENSICS_LUKS_NAME:=forensics_crypt}"

: "${SIFT_ENABLED:=true}"
: "${SIFT_HOST:=}"
: "${SIFT_USER:=sansforensics}"
: "${SSH_IDENTITY:=$HOME/.ssh/id_rsa}"
: "${SIFT_VMX:=}"

: "${MEMPROCFS_HOME:=$HOME/memprocfs}"
: "${MEMPROCFS_BIN:=$MEMPROCFS_HOME/memprocfs}"
: "${MEMPROCFS_EXPECTED_VERSION:=5.17.9}"
: "${MEMPROCFS_MOUNT:=/mnt/mem}"

: "${IMAGE_VOLATILITY3:=forensics-volatility3:2.7.0}"
: "${IMAGE_PLASO:=forensics-plaso:20240512}"
: "${IMAGE_MFT_TOOLS:=forensics-mft-tools:1.2.0.0}"

: "${HERMES_PROFILE_DIR:=$HOME/.hermes/profiles/forensics}"

export FORENSICS_HOME FORENSICS_VAULT_ENABLED FORENSICS_IMG FORENSICS_KEYFILE \
       FORENSICS_LUKS_NAME SIFT_ENABLED SIFT_HOST SIFT_USER SSH_IDENTITY \
       SIFT_VMX MEMPROCFS_HOME MEMPROCFS_BIN MEMPROCFS_EXPECTED_VERSION \
       MEMPROCFS_MOUNT IMAGE_VOLATILITY3 IMAGE_PLASO IMAGE_MFT_TOOLS \
       HERMES_PROFILE_DIR

# ── Derived helpers ────────────────────────────────────────────────────────

# Truthiness for the *_ENABLED flags.
is_enabled() {
    case "${1,,}" in
        true|yes|1|on) return 0 ;;
        *) return 1 ;;
    esac
}

# Is the SIFT VM configured at all? Unconfigured is a valid state — the lab
# degrades to host-only rather than pretending an unreachable host exists.
sift_configured() {
    is_enabled "$SIFT_ENABLED" && [ -n "$SIFT_HOST" ]
}

# SSH options, one token per line. Pass "interactive" to drop BatchMode, for
# commands that legitimately need to prompt (sudo password, host key accept).
#
# Callers must never filter this output with grep: each -o and its value are
# separate tokens, so removing a value line leaves a dangling -o and ssh dies
# with 'no argument after keyword "-o"'. Ask for the variant you want instead.
sift_ssh_opts() {
    local opts=(-o ConnectTimeout=10)
    [ "${1:-}" = "interactive" ] || opts+=(-o BatchMode=yes)
    opts+=(-o StrictHostKeyChecking=accept-new)
    [ -f "$SSH_IDENTITY" ] && opts+=(-i "$SSH_IDENTITY")
    printf '%s\n' "${opts[@]}"
}

# Locate a lab script whether we are running from the repo or from an
# installed FORENSICS_HOME/scripts copy.
forensics_script() {
    local name="$1"
    if [ -f "$FORENSICS_REPO/scripts/$name" ]; then
        echo "$FORENSICS_REPO/scripts/$name"
    elif [ -f "$FORENSICS_HOME/scripts/$name" ]; then
        echo "$FORENSICS_HOME/scripts/$name"
    else
        return 1
    fi
}

# Print the resolved configuration — used by doctor and by --show-config.
forensics_print_config() {
    echo "  Config file:    ${FORENSICS_CONF_LOADED:-<none — using defaults>}"
    echo "  FORENSICS_REPO: $FORENSICS_REPO"
    echo "  FORENSICS_HOME: $FORENSICS_HOME"
    echo "  Vault:          $(is_enabled "$FORENSICS_VAULT_ENABLED" && echo "enabled ($FORENSICS_IMG)" || echo "disabled")"
    echo "  SIFT VM:        $(sift_configured && echo "$SIFT_USER@$SIFT_HOST" || echo "not configured (host-only mode)")"
    echo "  MemProcFS:      $MEMPROCFS_BIN"
}
