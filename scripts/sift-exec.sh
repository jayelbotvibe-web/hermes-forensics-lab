#!/bin/bash
# Execute a command on the SIFT VM via SSH
# Usage: sift-exec.sh "fls -r /cases/evidence.E01"
set -euo pipefail
SIFT_HOST="${SIFT_HOST:-192.168.88.14}"
SIFT_USER="${SIFT_USER:-sansforensics}"
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$SIFT_USER@$SIFT_HOST" "$@"