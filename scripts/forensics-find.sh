#!/bin/bash
# ============================================================================
# forensics-find.sh — Record a finding to findings.json.
#
# Usage:  bash forensics-find.sh CASE_ID "Title" HIGH "volatility3 2.7.0" "windows.pslist" "EVID-001" "raw/vol3_pslist.csv" "Description of finding"
#
# Confidence: HIGH | MEDIUM | LOW | TENTATIVE
# ============================================================================
# Evidence root (override with env var)
FORENSICS_HOME="${FORENSICS_HOME:-$HOME/forensics}"

set -uo pipefail

CASE_ID="${1:?Usage: forensics-find.sh CASE_ID TITLE CONFIDENCE TOOL COMMAND EVID_REF RAW_OUTPUT FINDING [CROSS_VAL]}"
TITLE="${2:?}"
CONFIDENCE="${3:?}"
TOOL="${4:?}"
COMMAND="${5:?}"
EVID_REF="${6:?}"
RAW_OUTPUT="${7:?}"
FINDING="${8:?}"
CROSS_VAL="${9:-}"

FORENSICS_DIR="$FORENSICS_HOME"
CASE_DIR="$FORENSICS_DIR/cases/$CASE_ID"
FINDINGS_JSON="$CASE_DIR/findings.json"
# shellcheck disable=SC2034
EXAMINER="${USER:-examiner}"

if [ ! -d "$CASE_DIR" ]; then
    echo "ERROR: Case directory not found: $CASE_DIR" >&2
    exit 1
fi

# Validate confidence
case "$CONFIDENCE" in
    HIGH|MEDIUM|LOW|TENTATIVE) ;;
    *) echo "ERROR: Confidence must be HIGH, MEDIUM, LOW, or TENTATIVE" >&2; exit 1 ;;
esac

# Determine next finding ID
python3 -c "
import json, os

path = '$FINDINGS_JSON'
data = []
if os.path.exists(path) and os.path.getsize(path) > 0:
    try:
        data = json.load(open(path))
        if not isinstance(data, list):
            data = []
    except:
        pass

last_num = 0
for f in data:
    fid = f.get('id', 'F-niel-000')
    try:
        n = int(fid.split('-')[-1])
        if n > last_num:
            last_num = n
    except:
        pass

next_num = last_num + 1
finding_id = f'F-niel-{next_num:03d}'

entry = {
    'id': finding_id,
    'title': '''$(python3 -c "import json; print(json.dumps('$TITLE'))")''',
    'confidence': '$CONFIDENCE',
    'tool': '$TOOL',
    'command': '$COMMAND',
    'evidence_ref': '$EVID_REF',
    'raw_output': '$RAW_OUTPUT',
    'cross_validation': 'N/A (cross-validation removed in v4.2)',
    'finding': '''$(python3 -c "import json; print(json.dumps('$FINDING'))")'''
}

data.append(entry)
json.dump(data, open(path, 'w'), indent=2)
print(finding_id)
"

# shellcheck disable=SC2034
FINDING_ID=$?  # python3 prints to stdout so we can't catch easily — let me fix

# Actually let me do this differently — just print the ID
echo ""
echo "  ┌─────────────────────────────────────────┐"
echo "  │  Finding recorded: case/$CASE_ID"
echo "  │  File: findings.json"
echo "  └─────────────────────────────────────────┘"
