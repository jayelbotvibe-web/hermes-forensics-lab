#!/bin/bash
# ============================================================================
# audit-append.sh — Tamper-evident hash-chained audit log append.
#
# Usage:  bash audit-append.sh <actions.jsonl-path> '<json-record>'
#
# Thin wrapper around audit-append.py. Callers pass a JSON object (without
# prev_hash / entry_hash fields) and the script computes the chain link and
# appends the record.
#
# Example:
#   bash audit-append.sh /path/to/case/audit/actions.jsonl \
#       '{"case_id":"INC-2026-0719-0001","action":"case_open","timestamp":"2026-07-19T00:00:00+00:00"}'
# ============================================================================

set -uo pipefail

LOGFILE="${1:?Usage: audit-append.sh <actions.jsonl-path> '<json-record>'}"
RECORD="${2:?}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/audit-append.py" "$LOGFILE" "$RECORD"
