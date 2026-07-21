#!/bin/bash
# Pentest ↔ Forensics handoff — create a task for the forensics agent
# Usage: handoff.sh "Title" /path/to/evidence HIGH [sender_name]
set -euo pipefail

TITLE="${1:-New forensic task}"
EVIDENCE_PATH="${2:-}"
PRIORITY="${3:-MEDIUM}"
SENDER="${4:-pentest-agent}"
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
HANDOFF_DIR="${FORENSICS_HOME}/cases"
CASE_ID="INC-$(date +%Y-%m%d)-$(date +%H%M)"

mkdir -p "$HANDOFF_DIR/$CASE_ID/evidence"

if [ -n "$EVIDENCE_PATH" ] && [ -f "$EVIDENCE_PATH" ]; then
    cp "$EVIDENCE_PATH" "$HANDOFF_DIR/$CASE_ID/evidence/"
    HASH=$(sha256sum "$EVIDENCE_PATH" | cut -d' ' -f1)
    chmod 444 "$HANDOFF_DIR/$CASE_ID/evidence/$(basename "$EVIDENCE_PATH")"
else
    HASH=""
fi

cat > "$HANDOFF_DIR/$CASE_ID/handoff.json" << EOF
{
  "handoff_id": "H-$(date +%s)",
  "from": "${SENDER}",
  "to": "forensics-agent",
  "timestamp": "$(date -Iseconds)",
  "title": "${TITLE}",
  "priority": "${PRIORITY}",
  "evidence": [
    {
      "type": "see case directory",
      "path": "${HANDOFF_DIR}/${CASE_ID}/evidence/",
      "sha256": "${HASH}"
    }
  ],
  "status": "pending"
}
EOF

echo "Handoff created: ${HANDOFF_DIR}/${CASE_ID}/"
echo "Title: ${TITLE}"
echo "Priority: ${PRIORITY}"
echo "From: ${SENDER}"
echo ""
echo "Forensics agent: start with 'hermes -p forensics'"