#!/bin/bash
# ============================================================================
# install.sh — Set up the Hermes Forensics Lab on this machine.
#
#   ./install.sh                  # interactive, does everything
#   ./install.sh --yes            # accept all defaults, no prompts
#   ./install.sh --minimal        # host-only: no VM, no vault, no Hermes
#   ./install.sh --dry-run        # print what would happen, change nothing
#
# Targeted re-runs (safe at any time, each is idempotent):
#   ./install.sh --config-only    # just write forensics.conf
#   ./install.sh --images-only    # just build the 3 Docker images
#   ./install.sh --deps-only      # just the Python packages
#   ./install.sh --memprocfs-only # just MemProcFS
#   ./install.sh --profile-only   # just the Hermes agent profile
#
# This script never touches evidence and never overwrites an existing config
# without asking. The two heavyweight steps — the encrypted vault and the
# SIFT VM — are offered, not forced: the lab is useful without either.
# ============================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FORENSICS_REPO="$REPO_ROOT"
source "$REPO_ROOT/scripts/lib/common.sh"

ASSUME_YES=false
DRY_RUN=false
MINIMAL=false
ONLY=""

usage() { sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)         ASSUME_YES=true; shift ;;
        --dry-run)        DRY_RUN=true; shift ;;
        --minimal)        MINIMAL=true; shift ;;
        --config-only)    ONLY="config"; shift ;;
        --images-only)    ONLY="images"; shift ;;
        --deps-only)      ONLY="deps"; shift ;;
        --memprocfs-only) ONLY="memprocfs"; shift ;;
        --profile-only)   ONLY="profile"; shift ;;
        -h|--help)        usage ;;
        *)                die "unknown argument: $1 (try --help)" ;;
    esac
done

run() {
    if $DRY_RUN; then echo -e "      ${DIM}would run:${NC} $*"; return 0; fi
    "$@"
}

# ask <prompt> <default y|n>
ask() {
    local prompt="$1" default="${2:-y}" reply
    if $ASSUME_YES; then
        [ "$default" = "y" ]
        return
    fi
    if [ "$default" = "y" ]; then
        read -r -p "  $prompt [Y/n] " reply
        [[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]
    else
        read -r -p "  $prompt [y/N] " reply
        [[ "$reply" =~ ^[Yy]$ ]]
    fi
}

banner() {
    echo -e "${CYAN}${BOLD}"
    echo "  ╔════════════════════════════════════════════════════╗"
    echo "  ║      Hermes Forensics Lab — Installer              ║"
    echo "  ╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    $DRY_RUN && echo -e "  ${YELLOW}DRY RUN — nothing will be changed.${NC}\n"
    return 0
}

# ── Step: system prerequisites ─────────────────────────────────────────────

install_prereqs() {
    log_step "[1/7] System prerequisites"

    if [ "$(uname -s)" != "Linux" ]; then
        log_err "This lab requires Linux — found $(uname -s)."
        echo "      cryptsetup, FUSE, and the VM tooling have no macOS/Windows equivalent."
        echo "      The encyclopedia and verification scripts still work; see README."
        exit 1
    fi

    local missing=()
    for t in docker python3 ssh git curl unzip; do
        command -v "$t" >/dev/null 2>&1 || missing+=("$t")
    done
    is_enabled "$FORENSICS_VAULT_ENABLED" && ! $MINIMAL && \
        { command -v cryptsetup >/dev/null 2>&1 || missing+=(cryptsetup); }

    if [ ${#missing[@]} -eq 0 ]; then
        log_ok "All system prerequisites present"
        return 0
    fi

    log_warn "Missing: ${missing[*]}"
    local pkgs="${missing[*]}"
    pkgs="${pkgs/docker/docker.io}"
    pkgs="${pkgs/ssh/openssh-client}"

    if command -v apt-get >/dev/null 2>&1; then
        if ask "Install them with apt?" y; then
            log_info "Running apt — this takes a minute"
            run sudo apt-get update -qq >/dev/null 2>&1
            # Word splitting is intended: $pkgs is a space-separated package list.
            # shellcheck disable=SC2086
            run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pkgs \
                >/dev/null 2>&1 || log_warn "apt reported errors — continuing"
            log_ok "Installed: ${missing[*]}"
        else
            log_info "Skipped. Install manually: sudo apt install $pkgs"
        fi
    else
        log_warn "Not an apt system — install these yourself: ${missing[*]}"
    fi

    if command -v docker >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
        log_warn "Docker installed but not usable by this account."
        echo "      sudo systemctl enable --now docker"
        echo "      sudo usermod -aG docker $USER   # then log out and back in"
    fi
}

# ── Step: Python dependencies ──────────────────────────────────────────────

install_deps() {
    log_step "[2/7] Python packages"

    # WeasyPrint needs native libs; without them the import fails confusingly.
    if command -v apt-get >/dev/null 2>&1; then
        local sys_libs=(libpango-1.0-0 libpangoft2-1.0-0 libcairo2 libgdk-pixbuf-2.0-0)
        local need=()
        for lib in "${sys_libs[@]}"; do
            dpkg -s "$lib" >/dev/null 2>&1 || need+=("$lib")
        done
        if [ ${#need[@]} -gt 0 ]; then
            log_info "WeasyPrint needs: ${need[*]}"
            ask "Install them?" y && run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${need[@]}" >/dev/null 2>&1
        fi
    fi

    local pip_args=(--quiet -r "$REPO_ROOT/requirements.txt")
    # PEP 668 systems refuse a bare pip install into the system interpreter.
    if python3 -c 'import sysconfig,os; raise SystemExit(0 if os.path.exists(os.path.join(sysconfig.get_path("stdlib"),"EXTERNALLY-MANAGED")) else 1)' 2>/dev/null; then
        log_info "Externally-managed Python detected — installing with --user --break-system-packages"
        pip_args=(--user --break-system-packages "${pip_args[@]}")
    fi

    if $DRY_RUN; then
        run python3 -m pip install "${pip_args[@]}"
    elif python3 -m pip install "${pip_args[@]}"; then
        log_ok "jinja2, weasyprint, markitdown"
    else
        log_warn "pip install failed — HTML/PDF report generation will not work."
        echo "      Try a virtualenv:  python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt"
    fi
}

# ── Step: Docker images ────────────────────────────────────────────────────

install_images() {
    log_step "[3/7] Docker tool images"

    if ! docker info >/dev/null 2>&1; then
        log_warn "Docker daemon unreachable — skipping image builds."
        echo "      Fix Docker, then re-run: ./install.sh --images-only"
        return 0
    fi

    # tag:context — the tags must match what session-canary.sh probes.
    local builds=(
        "$IMAGE_VOLATILITY3:tools/volatility"
        "$IMAGE_PLASO:tools/plaso"
        "$IMAGE_MFT_TOOLS:tools/mft-tools"
    )
    local failed=()
    for spec in "${builds[@]}"; do
        local ctx="${spec##*:}"
        local tag="${spec%:*}"
        if docker image inspect "$tag" >/dev/null 2>&1; then
            log_ok "$tag (already built)"
            continue
        fi
        log_info "Building $tag — this pulls a few hundred MB"
        if run docker build -q -t "$tag" "$REPO_ROOT/$ctx" >/dev/null; then
            log_ok "$tag"
        else
            log_err "$tag failed to build"
            failed+=("$tag")
        fi
    done

    if [ ${#failed[@]} -gt 0 ]; then
        log_warn "${#failed[@]} image(s) failed — those tools will report DEGRADED."
        echo "      Retry individually: docker build -t <tag> tools/<dir>/"
    fi
}

# ── Step: MemProcFS ────────────────────────────────────────────────────────

install_memprocfs() {
    log_step "[4/7] MemProcFS"

    if [ -x "$MEMPROCFS_BIN" ]; then
        log_ok "Already installed at $MEMPROCFS_BIN"
        return 0
    fi
    if ! ask "Install MemProcFS v$MEMPROCFS_EXPECTED_VERSION to $MEMPROCFS_HOME?" y; then
        log_info "Skipped — host memory forensics will be unavailable"
        return 0
    fi

    command -v apt-get >/dev/null 2>&1 && {
        dpkg -s libfuse2t64 >/dev/null 2>&1 || dpkg -s libfuse2 >/dev/null 2>&1 || {
            log_info "Installing FUSE"
            run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libfuse2t64 lz4 >/dev/null 2>&1 \
                || run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libfuse2 lz4 >/dev/null 2>&1 \
                || log_warn "FUSE install failed — MemProcFS will not be able to mount"
        }
    }

    run mkdir -p "$MEMPROCFS_HOME"

    # Release assets are named MemProcFS_files_and_binaries_v<ver>-linux_<arch>-<builddate>.tar.gz.
    # The build-date suffix is unpredictable, so resolve the real asset from the
    # API rather than guessing a URL. Prefer the pinned version; fall back to
    # whatever the latest release offers for this architecture.
    local arch
    case "$(uname -m)" in
        x86_64)         arch="linux_x64" ;;
        aarch64|arm64)  arch="linux_aarch64" ;;
        *)              log_warn "Unsupported architecture $(uname -m) — install MemProcFS manually"
                        return 0 ;;
    esac

    log_info "Resolving the latest MemProcFS release for $arch"
    local api url=""
    api="$(curl -fsSL https://api.github.com/repos/ufrisk/MemProcFS/releases/latest 2>/dev/null)"
    if [ -n "$api" ]; then
        # Pinned version first, so a catalog pin actually means something.
        url="$(printf '%s' "$api" | grep -o "https://[^\"]*_v${MEMPROCFS_EXPECTED_VERSION}-${arch}[^\"]*\.tar\.gz" | head -1)"
        if [ -z "$url" ]; then
            url="$(printf '%s' "$api" | grep -o "https://[^\"]*-${arch}[^\"]*\.tar\.gz" | head -1)"
            if [ -n "$url" ]; then
                local actual
                actual="$(printf '%s' "$url" | grep -oE '_v[0-9]+\.[0-9]+\.[0-9]+' | tr -d '_v')"
                log_warn "v$MEMPROCFS_EXPECTED_VERSION not in the latest release — installing v$actual"
                echo "      The canary pins v$MEMPROCFS_EXPECTED_VERSION and will report a version mismatch."
                echo "      Either keep the pin and install v$MEMPROCFS_EXPECTED_VERSION by hand, or set"
                echo "      MEMPROCFS_EXPECTED_VERSION=$actual in your forensics.conf and update"
                echo "      tools/tool-catalog.yaml to match."
            fi
        fi
    fi

    if [ -z "$url" ]; then
        log_warn "Could not resolve a MemProcFS download for $arch."
        echo "      Download it from https://github.com/ufrisk/MemProcFS/releases"
        echo "      and extract to $MEMPROCFS_HOME"
        return 0
    fi

    local tmp; tmp="$(mktemp -d)"
    log_info "Downloading $(basename "$url")"
    if run curl -fsSL "$url" -o "$tmp/memprocfs.tar.gz"; then
        run tar xzf "$tmp/memprocfs.tar.gz" -C "$MEMPROCFS_HOME" --strip-components=1 2>/dev/null \
            || run tar xzf "$tmp/memprocfs.tar.gz" -C "$MEMPROCFS_HOME"
        run chmod +x "$MEMPROCFS_BIN" 2>/dev/null || true
        if $DRY_RUN || [ -x "$MEMPROCFS_BIN" ]; then
            log_ok "Installed to $MEMPROCFS_HOME"
        else
            log_warn "Extracted, but no executable at $MEMPROCFS_BIN — check the archive layout"
        fi
    else
        log_warn "Download failed: $url"
        echo "      Grab it manually from https://github.com/ufrisk/MemProcFS/releases"
        echo "      and extract to $MEMPROCFS_HOME"
    fi
    rm -rf "$tmp"
}

# ── Step: config file ──────────────────────────────────────────────────────

install_config() {
    log_step "[5/7] Configuration"

    local cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hermes-forensics"
    local cfg="$cfg_dir/forensics.conf"

    if [ -f "$cfg" ]; then
        log_ok "Config already exists at $cfg"
        ask "Reconfigure it?" n || return 0
        run cp "$cfg" "$cfg.bak"
        log_info "Backed up to $cfg.bak"
    fi

    run mkdir -p "$cfg_dir"

    local v_home="$FORENSICS_HOME" v_sift="" v_user="$SIFT_USER" v_vault="true"
    $MINIMAL && v_vault="false"

    if ! $ASSUME_YES && ! $MINIMAL; then
        echo ""
        read -r -p "  Evidence root [$FORENSICS_HOME]: " reply
        [ -n "$reply" ] && v_home="$reply"

        if ask "Encrypt evidence at rest with LUKS? (recommended)" y; then
            v_vault="true"
        else
            v_vault="false"
        fi

        echo ""
        echo "  The SIFT VM provides 8 filesystem-forensics tools (sleuthkit, foremost,"
        echo "  regripper...). Leave blank to run host-only — Docker tools still work."
        read -r -p "  SIFT VM address [none]: " reply
        [ -n "$reply" ] && v_sift="$reply"
        if [ -n "$v_sift" ]; then
            read -r -p "  SIFT VM username [$SIFT_USER]: " reply
            [ -n "$reply" ] && v_user="$reply"
        fi
    fi

    if $DRY_RUN; then
        echo -e "      ${DIM}would write:${NC} $cfg"
    else
        # Start from the documented example so every option stays discoverable,
        # then overwrite just the answers we collected.
        cp "$REPO_ROOT/forensics.conf.example" "$cfg"
        sed -i \
            -e "s|^FORENSICS_HOME=.*|FORENSICS_HOME=\"$v_home\"|" \
            -e "s|^FORENSICS_VAULT_ENABLED=.*|FORENSICS_VAULT_ENABLED=$v_vault|" \
            -e "s|^SIFT_HOST=.*|SIFT_HOST=\"$v_sift\"|" \
            -e "s|^SIFT_USER=.*|SIFT_USER=\"$v_user\"|" \
            -e "s|^SIFT_ENABLED=.*|SIFT_ENABLED=$([ -n "$v_sift" ] && echo true || echo false)|" \
            "$cfg"
        log_ok "Wrote $cfg"
    fi

    # Re-read so later steps and the closing summary see the new values.
    # FORENSICS_CONF_LOADED was resolved when common.sh was sourced, before this
    # file existed — without updating it the summary reports "no config file"
    # immediately after writing one.
    if ! $DRY_RUN; then
        FORENSICS_HOME="$v_home"; SIFT_HOST="$v_sift"; SIFT_USER="$v_user"
        FORENSICS_VAULT_ENABLED="$v_vault"
        FORENSICS_CONF_LOADED="$cfg"
        SIFT_ENABLED="$([ -n "$v_sift" ] && echo true || echo false)"
        export FORENSICS_HOME SIFT_HOST SIFT_USER FORENSICS_VAULT_ENABLED \
               FORENSICS_CONF_LOADED SIFT_ENABLED
    fi
}

# ── Step: evidence vault ───────────────────────────────────────────────────

install_vault() {
    log_step "[6/7] Evidence storage"

    if ! is_enabled "$FORENSICS_VAULT_ENABLED"; then
        log_info "Vault disabled — using the plain filesystem"
        run mkdir -p "$FORENSICS_HOME"/{cases,tools,scripts,fixtures,logs}
        log_ok "Created $FORENSICS_HOME skeleton"
        return 0
    fi

    if [ -f "$FORENSICS_IMG" ]; then
        log_ok "Vault already exists at $FORENSICS_IMG"
        return 0
    fi

    echo "  Evidence is stored in a LUKS-encrypted container."
    echo "  This needs sudo and asks you to choose a passphrase."
    if ask "Create it now?" y; then
        if $DRY_RUN; then
            echo -e "      ${DIM}would run:${NC} bash scripts/create-evidence-vault.sh"
        else
            bash "$REPO_ROOT/scripts/create-evidence-vault.sh" \
                || log_warn "Vault setup did not complete — re-run scripts/create-evidence-vault.sh"
        fi
    else
        log_info "Skipped. Create it later: bash scripts/create-evidence-vault.sh --size 60G"
    fi
}

# ── Step: lab files and agent profile ──────────────────────────────────────

install_profile() {
    log_step "[7/7] Lab files and agent profile"

    # The canary and the skill docs expect scripts and tool catalogs to be
    # reachable under FORENSICS_HOME, not only in the repo.
    if [ -d "$FORENSICS_HOME" ] || $DRY_RUN; then
        run mkdir -p "$FORENSICS_HOME"/{cases,tools,scripts,fixtures,logs}
        if $DRY_RUN; then
            echo -e "      ${DIM}would sync:${NC} scripts/ and tools/ into $FORENSICS_HOME"
        else
            cp -r "$REPO_ROOT/scripts/." "$FORENSICS_HOME/scripts/" 2>/dev/null || true
            cp -r "$REPO_ROOT/tools/." "$FORENSICS_HOME/tools/" 2>/dev/null || true
            chmod +x "$FORENSICS_HOME"/scripts/*.sh 2>/dev/null || true
            log_ok "Synced scripts and tool catalog into $FORENSICS_HOME"
        fi
    else
        log_warn "$FORENSICS_HOME does not exist — skipping lab file sync"
    fi

    if ! command -v hermes >/dev/null 2>&1; then
        log_info "Hermes not installed — skipping agent profile"
        echo "      The scripts and encyclopedia work without it."
        echo "      To use the agent: https://github.com/NousResearch/hermes"
        return 0
    fi

    if [ -f "$HERMES_PROFILE_DIR/config.yaml" ]; then
        log_ok "Agent profile already installed"
        return 0
    fi
    if ask "Install the forensics agent profile to $HERMES_PROFILE_DIR?" y; then
        run mkdir -p "$HERMES_PROFILE_DIR"
        if $DRY_RUN; then
            echo -e "      ${DIM}would copy:${NC} profile, persona, skills"
        else
            cp -r "$REPO_ROOT/hermes-forensics.profile/." "$HERMES_PROFILE_DIR/"
            cp "$REPO_ROOT/persona.md" "$HERMES_PROFILE_DIR/" 2>/dev/null || true
            cp -r "$REPO_ROOT/skills" "$HERMES_PROFILE_DIR/" 2>/dev/null || true
            log_ok "Installed profile, persona, and 7 skills"
            log_warn "Set your model and API key in $HERMES_PROFILE_DIR/config.yaml"
        fi
    fi
}

# ── Main ───────────────────────────────────────────────────────────────────

banner

case "$ONLY" in
    config)    install_config; exit 0 ;;
    images)    install_images; exit 0 ;;
    deps)      install_deps; exit 0 ;;
    memprocfs) install_memprocfs; exit 0 ;;
    profile)   install_profile; exit 0 ;;
esac

install_prereqs
install_deps
install_images
$MINIMAL || install_memprocfs
install_config
install_vault
install_profile

# ── Closing summary ────────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}${BOLD}────────────────────────────────────────────────────${NC}"
if $DRY_RUN; then
    echo -e "${YELLOW}Dry run complete — nothing was changed.${NC}"
    echo ""
    exit 0
fi

echo -e "${GREEN}${BOLD}Installation complete.${NC}"
echo ""
forensics_print_config
echo ""
echo "  Verify:  bash scripts/forensics-doctor.sh"

if [ -z "$SIFT_HOST" ] && is_enabled "$SIFT_ENABLED"; then
    echo ""
    echo -e "  ${DIM}No SIFT VM configured. To add one later (see INSTALL.md for"
    echo -e "  building the VM), then:${NC}"
    echo "      bash scripts/provision-sift.sh <vm-ip>"
fi

echo ""
echo "  Daily use:"
echo "      bash scripts/forensics-up.sh      # mount vault, start VM, run canary"
echo "      bash scripts/forensics-down.sh    # stop VM, unmount vault"
echo ""
