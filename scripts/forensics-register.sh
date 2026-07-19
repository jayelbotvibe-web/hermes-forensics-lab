#!/bin/bash
# ============================================================================
# forensics-register.sh — Register evidence in one command.
#
# Usage:  bash forensics-register.sh CASE_ID /path/to/evidence.file [source_url] [expected_sha256]
#
# What it does:
#   1. Hashes the evidence (SHA-256)
#   2. Verifies against expected hash (if provided)
#   3. Copies file into case/evidence/ (if not already there)
#   4. Sets read-only (chmod 444)
#   5. Updates evidence.json with evidence_id, filename, hash, source, timestamp
#   6. Logs to audit/actions.jsonl
#
# Example:
#   bash forensics-register.sh INC-2026-0624-0001 ~/Downloads/dump.mem \
#       "https://ctf.example.com/dump.zip" \
#       "3dc0d114859c0bde08d39155eaaa8f76392dd5121ca44ecb15652b3bf6049e35"
# ============================================================================
# Evidence root (override with env var)
FORENSICS_HOME="${FORENSICS_HOME:-$HOME/forensics}"

set -uo pipefail

CASE_ID="${1:?Usage: forensics-register.sh CASE_ID /path/to/file [source_url] [expected_sha256]}"
SRC_FILE="${2:?Usage: forensics-register.sh CASE_ID /path/to/file [source_url] [expected_sha256]}"
SOURCE_URL="${3:-manual}"
EXPECTED_SHA256="${4:-}"

FORENSICS_DIR="$FORENSICS_HOME"
CASE_DIR="$FORENSICS_DIR/cases/$CASE_ID"
EVIDENCE_DIR="$CASE_DIR/evidence"
EXAMINER="${USER:-examiner}"

if [ ! -d "$CASE_DIR" ]; then
    echo "ERROR: Case directory not found: $CASE_DIR" >&2
    echo "Create it first: bash forensics-case.sh \"description\"" >&2
    exit 1
fi

if [ ! -f "$SRC_FILE" ]; then
    echo "ERROR: Source file not found: $SRC_FILE" >&2
    exit 1
fi

FILENAME=$(basename "$SRC_FILE")
DEST_FILE="$EVIDENCE_DIR/$FILENAME"
TIMESTAMP=$(date -Iseconds)
EVIDENCE_JSON="$CASE_DIR/evidence.json"
AUDIT_LOG="$CASE_DIR/audit/actions.jsonl"

echo "=== Evidence Registration ==="
echo "  Case:     $CASE_ID"
echo "  File:     $FILENAME"
echo "  Source:   $SOURCE_URL"
echo ""

# ── Step 1: Hash ─────────────────────────────────────────────────────────

echo -n "  [1/5] Hashing... "
SHA256=$(sha256sum "$SRC_FILE" | awk '{print $1}')
echo "$SHA256"

# ── Step 2: Verify ────────────────────────────────────────────────────────

if [ -n "$EXPECTED_SHA256" ]; then
    echo -n "  [2/5] Verifying... "
    if [ "$SHA256" = "$EXPECTED_SHA256" ]; then
        echo "MATCH ✓"
    else
        echo "MISMATCH ✗"
        echo "    Expected: $EXPECTED_SHA256"
        echo "    Got:      $SHA256"
        echo "    ABORTING — hash mismatch"
        exit 1
    fi
else
    echo "  [2/5] No expected hash — skipping verification"
fi

# ── Step 3: Copy ──────────────────────────────────────────────────────────

if [ "$(realpath "$SRC_FILE")" = "$(realpath "$DEST_FILE" 2>/dev/null)" ] 2>/dev/null; then
    echo "  [3/5] File already in evidence directory"
else
    echo -n "  [3/5] Copying into case... "
    cp "$SRC_FILE" "$DEST_FILE"
    echo "done"
fi

# ── Step 4: Read-only ─────────────────────────────────────────────────────

echo -n "  [4/5] Setting read-only... "
chmod 444 "$DEST_FILE"
echo "done"

# ── Step 5: Register ──────────────────────────────────────────────────────

echo -n "  [5/5] Registering in evidence.json + audit trail... "

# Determine next evidence ID
if [ -f "$EVIDENCE_JSON" ] && [ -s "$EVIDENCE_JSON" ]; then
    NEXT_NUM=$(python3 -c "
import json, sys
try:
    data = json.load(open('$EVIDENCE_JSON'))
    if isinstance(data, list) and data:
        last = data[-1].get('evidence_id', 'EVID-000')
        num = int(last.split('-')[-1]) + 1
        print(num)
    else:
        print(1)
except: print(1)
" 2>/dev/null || echo 1)
else
    NEXT_NUM=1
fi
EVIDENCE_ID=$(printf "EVID-%03d" "$NEXT_NUM")

# Update evidence.json
python3 -c "
import json, os

entry = {
    'evidence_id': '$EVIDENCE_ID',
    'filename': '$FILENAME',
    'sha256': '$SHA256',
    'source': '$SOURCE_URL',
    'acquired_by': '$EXAMINER',
    'acquired_at': '$TIMESTAMP',
    'tool': 'sha256sum',
    'readonly': True,
    'path': '$DEST_FILE'
}

path = '$EVIDENCE_JSON'
data = []
if os.path.exists(path) and os.path.getsize(path) > 0:
    try:
        data = json.load(open(path))
        if not isinstance(data, list):
            data = []
    except:
        data = []
data.append(entry)
json.dump(data, open(path, 'w'), indent=2)
print('done', end='')
"

# Audit trail — tamper-evident hash-chained append
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT_RECORD=$(python3 -c "
import json, sys
rec = {
    'case_id': sys.argv[1],
    'action': 'evidence_registered',
    'timestamp': sys.argv[2],
    'evidence_id': sys.argv[3],
    'filename': sys.argv[4],
    'sha256': sys.argv[5]
}
print(json.dumps(rec, separators=(',', ':')))
" "$CASE_ID" "$TIMESTAMP" "$EVIDENCE_ID" "$FILENAME" "$SHA256")
bash "$SCRIPT_DIR/audit-append.sh" "$AUDIT_LOG" "$AUDIT_RECORD" >&2

echo ""

echo ""
echo "  ┌─────────────────────────────────────────┐"
echo "  │  EVID-$NEXT_NUM registered: $FILENAME"
echo "  │  SHA-256: $SHA256"
echo "  │  Path: $DEST_FILE"
echo "  └─────────────────────────────────────────┘"
echo ""
echo "$EVIDENCE_ID"
