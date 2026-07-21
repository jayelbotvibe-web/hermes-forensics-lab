#!/bin/bash
# sift-exec.sh — Run a command on the SIFT Workstation VM.
#   bash scripts/sift-exec.sh "fls -r -m / /cases/CASE_ID/evidence/image.E01"
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if ! sift_configured; then
    echo "error: no SIFT VM configured." >&2
    echo "  Set SIFT_HOST in your forensics.conf, or provision a VM:" >&2
    echo "      bash scripts/provision-sift.sh <vm-ip>" >&2
    exit 1
fi

# shellcheck disable=SC2046
exec ssh $(sift_ssh_opts | tr '\n' ' ') "$SIFT_USER@$SIFT_HOST" "$@"