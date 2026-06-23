#!/bin/bash
# Initialize a forensic case directory
# Usage: init-case.sh "Case description"
set -euo pipefail

FORENSICS_HOME="${FORENSICS_HOME:-$HOME/forensics}"
DESCRIPTION="${1:-Untitled investigation}"
DATE=$(date +%Y-%m%d)
TIME=$(date +%H%M)
CASE_ID="INC-${DATE}-${TIME}"
CASE_DIR="${FORENSICS_HOME}/cases/${CASE_ID}"

mkdir -p "${CASE_DIR}"/{evidence,raw,reports,audit}

cat > "${CASE_DIR}/CASE.yaml" << EOF
case_id: ${CASE_ID}
status: active
opened: $(date -Iseconds)
examiner: ${EXAMINER:-niel}
description: "${DESCRIPTION}"
EOF

echo '{"case_id": "'${CASE_ID}'", "action": "case_open", "timestamp": "'$(date -Iseconds)'"}' \
  >> "${CASE_DIR}/audit/actions.jsonl"

echo "[]" > "${CASE_DIR}/evidence.json"

echo "Case created: ${CASE_DIR}"
echo "ID: ${CASE_ID}"
echo "Start: hermes -p forensics"