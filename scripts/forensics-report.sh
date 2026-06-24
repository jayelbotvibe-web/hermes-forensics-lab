#!/bin/bash
# ============================================================================
# forensics-report.sh — Generate forensic report from case JSON files.
#
# Usage:  bash forensics-report.sh CASE_ID [output_path]
#
# Reads findings.json, timeline.json, tool_versions.json, evidence.json, CASE.yaml
# from the case directory. Generates a complete markdown forensic report.
# ============================================================================
set -uo pipefail

CASE_ID="${1:?Usage: forensics-report.sh CASE_ID [output_path]}"
OUTPUT="${2:-}"

FORENSICS_DIR="/home/niel/forensics"
CASE_DIR="$FORENSICS_DIR/cases/$CASE_ID"

if [ ! -d "$CASE_DIR" ]; then
    echo "ERROR: Case directory not found: $CASE_DIR" >&2
    exit 1
fi

[ -z "$OUTPUT" ] && OUTPUT="$CASE_DIR/reports/forensic-report.md"

# ── Read case metadata ────────────────────────────────────────────────────

CASE_YAML="$CASE_DIR/CASE.yaml"
FINDINGS_JSON="$CASE_DIR/findings.json"
TIMELINE_JSON="$CASE_DIR/timeline.json"
EVIDENCE_JSON="$CASE_DIR/evidence.json"
TOOL_VERSIONS_JSON="$CASE_DIR/tool_versions.json"

DESCRIPTION="Unknown case"
[ -f "$CASE_YAML" ] && DESCRIPTION=$(grep "^description:" "$CASE_YAML" | sed 's/^description: *"//' | tr -d '"' | head -1)
EXAMINER="niel"
[ -f "$CASE_YAML" ] && EXAMINER=$(grep "^examiner:" "$CASE_YAML" | awk '{print $2}' || echo "niel")

TIMESTAMP=$(date -Iseconds)

# ── Generate report ───────────────────────────────────────────────────────

mkdir -p "$(dirname "$OUTPUT")"

cat > "$OUTPUT" << 'HEADER'
# Forensic Analysis Report

HEADER

cat >> "$OUTPUT" << EOF
**Case ID:** $CASE_ID  
**Description:** $DESCRIPTION  
**Examiner:** $EXAMINER  
**Generated:** $TIMESTAMP  
**Classification:** UNCLASSIFIED  

---

## Executive Summary

EOF

# Count findings by confidence
HIGH_COUNT=0; MED_COUNT=0; LOW_COUNT=0
if [ -f "$FINDINGS_JSON" ] && [ -s "$FINDINGS_JSON" ]; then
    HIGH_COUNT=$(python3 -c "
import json
data=json.load(open('$FINDINGS_JSON'))
print(sum(1 for f in data if f.get('confidence')=='HIGH'))
" 2>/dev/null || echo 0)
    MED_COUNT=$(python3 -c "
import json
data=json.load(open('$FINDINGS_JSON'))
print(sum(1 for f in data if f.get('confidence')=='MEDIUM'))
" 2>/dev/null || echo 0)
    LOW_COUNT=$(python3 -c "
import json
data=json.load(open('$FINDINGS_JSON'))
print(sum(1 for f in data if f.get('confidence') in ('LOW','TENTATIVE')))
" 2>/dev/null || echo 0)
fi

echo "**Findings:** ${HIGH_COUNT} HIGH, ${MED_COUNT} MEDIUM, ${LOW_COUNT} LOW/TENTATIVE" >> "$OUTPUT"
echo "" >> "$OUTPUT"
echo "*(Executive summary to be written by examiner)*" >> "$OUTPUT"
echo "" >> "$OUTPUT"
echo "---" >> "$OUTPUT"

# ── Evidence Registry ─────────────────────────────────────────────────────

cat >> "$OUTPUT" << 'EOF'

## Evidence Registry

| Evidence ID | Filename | SHA-256 | Source |
|-------------|----------|---------|--------|
EOF

if [ -f "$EVIDENCE_JSON" ] && [ -s "$EVIDENCE_JSON" ]; then
    python3 -c "
import json
data = json.load(open('$EVIDENCE_JSON'))
for e in data:
    sha = (e.get('sha256') or e.get('sha256_verified') or 'N/A')[:16] + '...'
    src = e.get('source', 'N/A')[:50]
    print(f\"| {e['evidence_id']} | {e['filename']} | {sha} | {src} |\")
" 2>/dev/null >> "$OUTPUT" || echo "| - | No evidence registered | - | - |" >> "$OUTPUT"
else
    echo "| - | No evidence registered | - | - |" >> "$OUTPUT"
fi

# ── Tools ──────────────────────────────────────────────────────────────────

cat >> "$OUTPUT" << 'EOF'

---

## Tools Deployed

EOF

if [ -f "$TOOL_VERSIONS_JSON" ] && [ -s "$TOOL_VERSIONS_JSON" ]; then
    echo '```' >> "$OUTPUT"
    python3 -c "
import json
data = json.load(open('$TOOL_VERSIONS_JSON'))
for name, info in data.items():
    if isinstance(info, dict):
        ver = info.get('version', '?')
        runtime = info.get('runtime', '?')
        status = '✅' if info.get('validated') else '⚠️'
        print(f'  {name:20s} {ver:15s} {runtime:12s} {status}')
" 2>/dev/null >> "$OUTPUT" || true
    echo '```' >> "$OUTPUT"
else
    echo "*(Tool versions not recorded)*" >> "$OUTPUT"
fi

# ── Findings ───────────────────────────────────────────────────────────────

cat >> "$OUTPUT" << 'EOF'

---

## Detailed Findings

EOF

if [ -f "$FINDINGS_JSON" ] && [ -s "$FINDINGS_JSON" ]; then
    python3 -c "
import json

data = json.load(open('$FINDINGS_JSON'))
for f in data:
    fid = f.get('id', '?')
    title = f.get('title', 'Untitled')
    conf = f.get('confidence', '?')
    tool = f.get('tool', '?')
    cmd = f.get('command', '?')
    evid = f.get('evidence_ref', '?')
    raw = f.get('raw_output', '?')
    finding = f.get('finding', '')
    cross = f.get('cross_validation', '')

    icon = {'HIGH': '🔴', 'MEDIUM': '🟡', 'LOW': '🟢', 'TENTATIVE': '⚪'}.get(conf, '⚪')

    print(f'''
### {icon} {fid}: {title}

**Confidence:** {conf}  
**Tool:** {tool}  
**Command:** \`{cmd}\`  
**Evidence:** {evid}  
**Raw output:** \`{raw}\`  
**Cross-validation:** {cross or 'None'}

{finding}

---
''')
" 2>/dev/null >> "$OUTPUT" || echo "*(Error reading findings)*" >> "$OUTPUT"
else
    echo "*(No findings recorded)*" >> "$OUTPUT"
fi

# ── Timeline ───────────────────────────────────────────────────────────────

cat >> "$OUTPUT" << 'EOF'

## Incident Timeline

| Timestamp (UTC) | Event | Source |
|-----------------|-------|--------|
EOF

if [ -f "$TIMELINE_JSON" ] && [ -s "$TIMELINE_JSON" ]; then
    python3 -c "
import json
data = json.load(open('$TIMELINE_JSON'))
for t in data:
    ts = t.get('timestamp', '?')
    event = t.get('event', '?')[:80]
    src = t.get('source', '?')[:30]
    print(f'| {ts} | {event} | {src} |')
" 2>/dev/null >> "$OUTPUT" || echo "| - | (Error reading timeline) | - |" >> "$OUTPUT"
else
    echo "| - | (No timeline events recorded) | - |" >> "$OUTPUT"
fi

# ── Footer ─────────────────────────────────────────────────────────────────

cat >> "$OUTPUT" << EOF

---

> **Report Generated:** $TIMESTAMP  
> **Hermes Forensics Agent** — Automated report from case JSON files  
> **Case directory:** $CASE_DIR
EOF

echo ""
echo "═══════════════════════════════════════════════"
echo "  Report generated: $OUTPUT"
echo "  Case: $CASE_ID"
echo "  Findings: $HIGH_COUNT HIGH, $MED_COUNT MEDIUM, $LOW_COUNT LOW/TENTATIVE"
echo "═══════════════════════════════════════════════"
echo ""
echo "$OUTPUT"
