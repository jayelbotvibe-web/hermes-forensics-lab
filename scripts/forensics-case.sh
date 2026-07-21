#!/bin/bash
# ============================================================================
# forensics-case.sh — Rapid case initialization.
#
# Usage:  CASE_ID=$(bash ~/forensics/scripts/forensics-case.sh "Case Description")
#         bash ~/forensics/scripts/forensics-case.sh "Case Description"  (see output)
#
# What it does:
#   1. Generates case ID: INC-YYYY-MMDD-NNNN
#   2. Creates full directory structure
#   3. Writes CASE.yaml, empty evidence.json/findings.json/timeline.json
#   4. Initializes audit/actions.jsonl
#   5. Prints banner to stderr, CASE_ID to stdout (so $(...) works cleanly)
#
# Example:
#   CASE_ID=$(bash ~/forensics/scripts/forensics-case.sh "BelkaCTF 7")
#   echo "Working in $FORENSICS_HOME/cases/$CASE_ID"
# ============================================================================
# Evidence root (override with env var)
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

set -uo pipefail

DESCRIPTION="${1:-Unnamed case}"

case "$DESCRIPTION" in
    --help|-h)
        echo "Usage: bash forensics-case.sh \"Case Description\"" >&2
        echo "" >&2
        echo "  Prints case ID to stdout for capture:  CASE_ID=\$(bash forensics-case.sh \"...\")" >&2
        exit 0 ;;
esac

FORENSICS_DIR="$FORENSICS_HOME"
CASES_DIR="$FORENSICS_DIR/cases"
EXAMINER="${USER:-examiner}"

# Generate case ID
DATE_PREFIX=$(date -u +%Y-%m%d)
NEXT_NUM=1
EXISTING=$(find "$CASES_DIR" -maxdepth 1 -type d -name "INC-${DATE_PREFIX}-*" 2>/dev/null | \
    sed 's/.*-//' | sort -n | tail -1)
if [ -n "$EXISTING" ] && [[ "$EXISTING" =~ ^[0-9]+$ ]]; then
    NEXT_NUM=$((10#$EXISTING + 1))
fi
CASE_ID=$(printf "INC-%s-%04d" "$DATE_PREFIX" "$NEXT_NUM")
CASE_DIR="$CASES_DIR/$CASE_ID"
TIMESTAMP=$(date -Iseconds)

# Create structure
mkdir -p "$CASE_DIR"/{evidence,raw,reports,audit}

# CASE.yaml
cat > "$CASE_DIR/CASE.yaml" << EOF
case_id: $CASE_ID
status: active
opened: "$TIMESTAMP"
examiner: $EXAMINER
description: "$DESCRIPTION"
EOF

# Empty templates
echo '[]' > "$CASE_DIR/evidence.json"
echo '[]' > "$CASE_DIR/findings.json"
echo '[]' > "$CASE_DIR/timeline.json"

# Audit trail — tamper-evident hash-chained append
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT_LOG="$CASE_DIR/audit/actions.jsonl"
AUDIT_RECORD=$(python3 -c "
import json, sys
rec = {
    'case_id': sys.argv[1],
    'action': 'case_open',
    'timestamp': sys.argv[2],
    'examiner': sys.argv[3],
    'description': sys.argv[4]
}
print(json.dumps(rec, separators=(',', ':')))
" "$CASE_ID" "$TIMESTAMP" "$EXAMINER" "$DESCRIPTION")
bash "$SCRIPT_DIR/audit-append.sh" "$AUDIT_LOG" "$AUDIT_RECORD" >&2

# Banner → stderr so $(...) capture stays clean
{
    echo ""
    echo "═══════════════════════════════════════════════"
    echo "  Case created: $CASE_ID"
    echo "  Path:         $CASE_DIR"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "  Structure:"
    echo "  ├── CASE.yaml"
    echo "  ├── evidence.json       (empty — register evidence here)"
    echo "  ├── findings.json       (empty — add findings here)"
    echo "  ├── timeline.json       (empty — add events here)"
    echo "  ├── evidence/           ← copy evidence here, then chmod 444"
    echo "  ├── raw/                ← tool output goes here"
    echo "  ├── reports/            ← final reports"
    echo "  └── audit/actions.jsonl ← chain of custody"
    echo ""
    echo "  Next: copy evidence → hash → register in evidence.json"
    echo ""
} >&2

# CASE_ID → stdout (only this line)
echo "$CASE_ID"
