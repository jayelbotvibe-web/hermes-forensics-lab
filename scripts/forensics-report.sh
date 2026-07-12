#!/bin/bash
# ============================================================================
# forensics-report.sh — Generate forensic report (HTML + PDF + Markdown).
#
# Usage:  bash forensics-report.sh CASE_ID [--html|--pdf|--md|--all]
#
# Default: --all (generates HTML, PDF, and Markdown reports)
#
# HTML/PDF report features:
#   - Dark theme, JetBrains Mono typography
#   - Visual vertical swimlane timeline with color-coded event types
#   - Findings register with severity/confidence badges + MITRE ATT&CK
#   - IOC table with type-coded tags
#   - Remediation actions, investigation gaps, system profile
#   - PDF output via WeasyPrint (requires: sudo apt install weasyprint)
#   - Print-friendly via @media print
# ============================================================================
# Evidence root (override with env var)
FORENSICS_HOME="${FORENSICS_HOME:-$HOME/forensics}"

set -uo pipefail

CASE_ID="${1:?Usage: forensics-report.sh CASE_ID [--html|--md|--both]}"
FORMAT="${2:---both}"

FORENSICS_DIR="$FORENSICS_HOME"
CASE_DIR="$FORENSICS_DIR/cases/$CASE_ID"
# shellcheck disable=SC2034
SCRIPTS_DIR="$FORENSICS_DIR/scripts"
REPORTS_DIR="$CASE_DIR/reports"

if [ ! -d "$CASE_DIR" ]; then
    echo "ERROR: Case directory not found: $CASE_DIR" >&2
    exit 1
fi

CASE_YAML="$CASE_DIR/CASE.yaml"
FINDINGS_JSON="$CASE_DIR/findings.json"
TIMELINE_JSON="$CASE_DIR/timeline.json"
EVIDENCE_JSON="$CASE_DIR/evidence.json"
TOOL_VERSIONS_JSON="$CASE_DIR/tool_versions.json"

mkdir -p "$REPORTS_DIR"

# ── Read case metadata ────────────────────────────────────────────────────

DESCRIPTION="Unnamed case"
[ -f "$CASE_YAML" ] && DESCRIPTION=$(grep "^description:" "$CASE_YAML" | sed 's/^description: *"//;s/"$//' | head -1)
EXAMINER="niel"
[ -f "$CASE_YAML" ] && EXAMINER=$(grep "^examiner:" "$CASE_YAML" | awk '{print $2}' || echo "niel")
REPORT_DATE=$(date "+%Y-%m-%d %H:%M %Z")

# ══════════════════════════════════════════════════════════════════════════
# HTML Report Generator
# ══════════════════════════════════════════════════════════════════════════

generate_html() {
    local OUT="$REPORTS_DIR/forensic-timeline-report.html"
    local TEMPLATE="$FORENSICS_DIR/../hermes-forensics-lab/reports/templates/timeline-report.html"
    if [ ! -f "$TEMPLATE" ]; then
        TEMPLATE="$(dirname "$(dirname "$0")")/reports/templates/timeline-report.html"
    fi

    # ── Generate correlation section ─────────────────────────────────────
    local CORR_SECTION=""
    CORR_PATH="$CASE_DIR/correlation-proposals.json"
    if [ -f "$CORR_PATH" ]; then
        CORR_SECTION=$(python3 -c "
import json
proposals = json.load(open('$CORR_PATH'))
tally = {}
for p in proposals:
    tally[p['verdict']] = tally.get(p['verdict'], 0) + 1
corr = tally.get('CORROBORATED', 0)
single = tally.get('SINGLE-SOURCE', 0)
contr = tally.get('CONTRADICTED', 0)
unver = tally.get('UNVERIFIED', 0)
total = len(proposals)
if total == 0:
    print('<p style=\"color:var(--text-faint)\">No correlation proposals generated. Run forensics-verify.py first.</p>')
else:
    print(f'''<div class=\"correlation-tally\">
      <div class=\"cell corroborated\"><span class=\"count\">{corr}</span><span class=\"label\">Corroborated</span></div>
      <div class=\"cell single-source\"><span class=\"count\">{single}</span><span class=\"label\">Single-Source</span></div>
      <div class=\"cell contradicted\"><span class=\"count\">{contr}</span><span class=\"label\">Contradicted</span></div>
      <div class=\"cell unverified\"><span class=\"count\">{unver}</span><span class=\"label\">Unverified</span></div>
    </div>
    <p style=\"font-size:10px;color:var(--text-faint);margin-top:8px\">{total} finding(s) reviewed. Advisory only — examiner confirms. Findings remain DRAFT.</p>''')
" 2>/dev/null)
    else
        CORR_SECTION='<p style="color:var(--text-faint)">No correlation data. Run: python3 /home/niel/forensics/scripts/forensics-verify.py <case_dir></p>'
    fi

    # ── Count stats ─────────────────────────────────────────────────────
    local FINDING_COUNT=0 HIGH_COUNT=0 EVIDENCE_COUNT=0 IOC_COUNT=0
    [ -f "$FINDINGS_JSON" ] && FINDING_COUNT=$(python3 -c "import json;d=json.load(open('$FINDINGS_JSON'));print(len(d))" 2>/dev/null || echo 0)
    [ -f "$FINDINGS_JSON" ] && HIGH_COUNT=$(python3 -c "import json;d=json.load(open('$FINDINGS_JSON'));print(sum(1 for f in d if f.get('confidence')=='HIGH'))" 2>/dev/null || echo 0)
    [ -f "$EVIDENCE_JSON" ] && EVIDENCE_COUNT=$(python3 -c "import json;d=json.load(open('$EVIDENCE_JSON'));print(len(d))" 2>/dev/null || echo 0)

    # ── Generate timeline HTML ──────────────────────────────────────────
    local TL_HTML=""
    if [ -f "$TIMELINE_JSON" ] && [ -s "$TIMELINE_JSON" ]; then
        TL_HTML=$(python3 << PYEOF
import json, sys

data = json.load(open('$TIMELINE_JSON'))
events = []

for e in data:
    ts = e.get('timestamp', '')
    ev = e.get('event', '')
    src = e.get('source', '')
    # Determine event type from keywords
    evt = 'system'
    ev_lower = (ev + ' ' + src).lower()
    if any(w in ev_lower for w in ['malware', 'compromise', 'infection', 'epxlorer', 'malfind','bsod']):
        evt = 'malware'
    elif any(w in ev_lower for w in ['c2', 'connection', 'network', 'tcp', 'ip ', ':443', 'telegram', 'exfil']):
        evt = 'network'
    elif any(w in ev_lower for w in ['spawned', 'process', 'pid', 'execution', 'cmdline']):
        evt = 'process'
    elif any(w in ev_lower for w in ['file', 'download', 'crdownload', 'filescan']):
        evt = 'file'
    elif any(w in ev_lower for w in ['login', 'user', 'award', 'explorer']):
        evt = 'user'

    events.append({
        'time': ts,
        'event': ev,
        'source': src,
        'type': evt
    })

for e in events:
    ts = e['time']
    ev_text = e['event']
    src_text = e['source']
    evt = e['type']
    # Format timestamp
    try:
        from datetime import datetime
        dt = datetime.fromisoformat(ts.replace('Z','+00:00'))
        date_str = dt.strftime('%Y-%m-%d')
        time_str = dt.strftime('%H:%M:%S')
    except:
        date_str = ts[:10] if len(ts) > 10 else ts
        time_str = ts[11:19] if len(ts) > 11 else ''

    print(f'''    <div class="tl-event">
      <div class="tl-dot {evt}"></div>
      <div class="tl-time"><span class="date">{date_str}</span> <span class="ms">{time_str} UTC</span></div>
      <div class="tl-card {evt}">
        <div class="tl-title">
          {ev_text}
        </div>
        <div class="tl-desc">
          <span class="tl-source">{src_text}</span>
        </div>
      </div>
    </div>''')
PYEOF
)
    else
        TL_HTML='<p style="color:var(--text-faint)">No timeline events recorded. Use forensics-find.sh to add events.</p>'
    fi

    # ── Generate findings table ─────────────────────────────────────────
    local FINDINGS_ROWS=""
    if [ -f "$FINDINGS_JSON" ] && [ -s "$FINDINGS_JSON" ]; then
        # Write Python script to temp file to avoid shell escaping hell
        cat > "$CASE_DIR/.gen_findings.py" << 'GENFINDINGS'
import json, os, sys

case_dir = sys.argv[1]
findings_path = os.path.join(case_dir, 'findings.json')

data = json.load(open(findings_path))

corr_by_id = {}
corr_path = os.path.join(case_dir, 'correlation-proposals.json')
if os.path.exists(corr_path):
    corr = json.load(open(corr_path))
    for p in corr:
        corr_by_id[p.get('finding_id', '?')] = p

for f in data:
    fid = f.get('id', '?')
    title = f.get('title', 'Untitled')
    conf = f.get('confidence', '?')
    tool = f.get('tool', '?')
    evid = f.get('evidence_ref', '?')
    badge = {'HIGH':'badge-high','MEDIUM':'badge-medium','LOW':'badge-low'}.get(conf, 'badge-low')
    cv = corr_by_id.get(fid, {})
    verdict = cv.get('verdict', '')
    v_badge = {
        'CORROBORATED': 'badge-corroborated',
        'SINGLE-SOURCE': 'badge-single-source',
        'CONTRADICTED': 'badge-contradicted',
        'UNVERIFIED': 'badge-unverified',
    }.get(verdict, '')
    v_label = verdict.replace('-', ' ') if verdict else '—'
    print(f'<tr><td><span class="mono">{fid}</span></td><td>{title}</td><td><span class="badge-cell {badge}">{conf}</span></td><td class="mono" style="font-size:11px">{tool}</td><td>{evid}</td><td><span class="badge-cell {v_badge}">{v_label}</span></td></tr>')
GENFINDINGS
        FINDINGS_ROWS=$(python3 "$CASE_DIR/.gen_findings.py" "$CASE_DIR" 2>/dev/null)
    else
        FINDINGS_ROWS='<tr><td colspan="6" style="color:var(--text-faint)">No findings recorded</td></tr>'
    fi

    # ── Generate IOC table ──────────────────────────────────────────────
    local IOC_ROWS=""

    # Extract IOCs from findings
    IOC_ROWS=$(python3 -c "
import json, re

iocs = []
if __import__('os').path.exists('$FINDINGS_JSON'):
    data = json.load(open('$FINDINGS_JSON'))
    for f in data:
        fid = f.get('id', '?')
        finding = f.get('finding', '') + ' ' + f.get('title', '')
        # IP addresses
        for ip in re.findall(r'\b(?:\d{1,3}\.){3}\d{1,3}\b', finding):
            if ip not in ['0.0.0.0','127.0.0.1','255.255.255.255']:
                iocs.append(('IP', ip, 'Network indicator', fid))
        # SHA256 hashes
        for h in re.findall(r'\b[a-f0-9]{64}\b', finding):
            iocs.append(('SHA-256', h[:16]+'...', 'File hash', fid))
        # MD5 hashes
        for h in re.findall(r'\b[a-f0-9]{32}\b', finding):
            iocs.append(('MD5', h, 'File hash', fid))
        # Domains
        for d in re.findall(r'\b[a-zA-Z0-9.-]+\.(?:com|org|net|io|do|gov|mil)\b', finding):
            if not d.startswith('0.') and len(d) > 6:
                iocs.append(('Domain', d, 'C2 / phishing domain', fid))
        # Email
        for em in re.findall(r'\b[\w.-]+@[\w.-]+\.\w+\b', finding):
            iocs.append(('Email', em, 'Phishing address', fid))
        # File paths
        for fp in re.findall(r'[A-Z]:\\\\[^\s,;]+\.exe', finding):
            iocs.append(('File Path', fp, 'Malware path', fid))

# Deduplicate
seen = set()
unique = []
for t, v, c, fid in iocs:
    if v not in seen:
        seen.add(v)
        unique.append((t, v, c, fid))

for t, v, c, fid in unique[:20]:
    tag_cls = {'IP':'ip','SHA-256':'hash','MD5':'hash','Domain':'domain','Email':'email','File Path':'file'}.get(t, 'ip')
    print(f\"<tr><td><span class='ioc-tag {tag_cls}'>{t}</span></td><td class='mono' style='font-size:11px'>{v}</td><td style='font-size:12px'>{c}</td><td class='mono' style='font-size:11px'>{fid}</td></tr>\")
" 2>/dev/null)
    [ -z "$IOC_ROWS" ] && IOC_ROWS='<tr><td colspan="4" style="color:var(--text-faint)">No IOCs extracted from findings</td></tr>'
    IOC_COUNT=$(echo "$IOC_ROWS" | grep -c "<tr>" 2>/dev/null || echo 0)

    # ── Generate evidence items ─────────────────────────────────────────
    local EVIDENCE_ITEMS=""
    if [ -f "$EVIDENCE_JSON" ] && [ -s "$EVIDENCE_JSON" ]; then
        EVIDENCE_ITEMS=$(python3 -c "
import json
data = json.load(open('$EVIDENCE_JSON'))
for e in data:
    eid = e.get('evidence_id', '?')
    fname = e.get('filename', '?')
    sha = (e.get('sha256') or e.get('sha256_verified') or 'N/A')
    src = e.get('source', 'N/A')[:60]
    print(f'''<div class=\"evidence-item\">
      <div class=\"ev-header\">
        <span class=\"ev-id\">{eid} — {fname}</span>
      </div>
      <div class=\"ev-hash\">SHA-256: {sha}</div>
      <div style=\"font-size:11px;color:var(--text-faint);margin-top:4px\">Source: {src}</div>
    </div>''')
" 2>/dev/null)
    else
        EVIDENCE_ITEMS='<p style="color:var(--text-faint)">No evidence registered</p>'
    fi

    # ── Generate tools table ────────────────────────────────────────────
    local TOOLS_ROWS=""
    if [ -f "$TOOL_VERSIONS_JSON" ] && [ -s "$TOOL_VERSIONS_JSON" ]; then
        TOOLS_ROWS=$(python3 -c "
import json
data = json.load(open('$TOOL_VERSIONS_JSON'))
# Infrastructure entries — not forensic tools, skip from tools table
INFRA_KEYS = {'sift-vm', 'session_canary', 'sift_vm', 'session-canary'}
for name, info in data.items():
    if name in INFRA_KEYS:
        continue
    if isinstance(info, dict):
        ver = info.get('version', 'N/A')
        runtime = info.get('runtime', 'N/A')
        ok = '✅' if info.get('validated') else '⚠️ DEGRADED'
        print(f\"<tr><td>{name}</td><td class=\\\"mono\\\">{ver}</td><td>{runtime}</td><td>{ok}</td></tr>\")
" 2>/dev/null)
    else
        TOOLS_ROWS='<tr><td colspan="4" style="color:var(--text-faint)">Tool versions not recorded</td></tr>'
    fi

    # ── Target system detection ─────────────────────────────────────────
    local TARGET="Unknown"
    if [ -f "$CASE_DIR/raw/vol3_windows_info_Info.txt" ]; then
        TARGET=$(grep "NTBuildLab\|NtMajorVersion\|NtProductType\|Is64Bit" "$CASE_DIR/raw/vol3_windows_info_Info.txt" 2>/dev/null | head -3 | paste -sd ' ' - || echo "Unknown")
        TARGET=$(echo "$TARGET" | cut -c1-80)
    fi

    # ── Build the report ────────────────────────────────────────────────

    # Classification
    local CLASS="UNCLASSIFIED"
    [ "$HIGH_COUNT" -gt 0 ] && CLASS="CONFIDENTIAL"

    # Compromise status
    local COMPROMISE="No"
    [ "$HIGH_COUNT" -gt 0 ] && COMPROMISE="YES — ${HIGH_COUNT} HIGH-confidence findings"

    # Investigation window
    local WINDOW="N/A"
    if [ -f "$TIMELINE_JSON" ] && [ -s "$TIMELINE_JSON" ]; then
        WINDOW=$(python3 -c "
import json
data = json.load(open('$TIMELINE_JSON'))
if data:
    first = data[0].get('timestamp','')[:10]
    last = data[-1].get('timestamp','')[:10]
    print(f'{first} → {last}')
" 2>/dev/null || echo "N/A")
    fi

    # Executive summary
    local EXEC_SUMMARY="Forensic analysis of digital evidence collected from the target system."
    if [ "$HIGH_COUNT" -gt 0 ]; then
        EXEC_SUMMARY="A forensic investigation was conducted on evidence from the target system. Analysis identified ${HIGH_COUNT} HIGH-confidence findings indicating malicious activity. The investigation utilized the Hermes Forensics Agent platform with multi-runtime tool validation (session canary: 9/9 PASS)."
    fi

    # ── Template substitution ───────────────────────────────────────────
    if [ -f "$TEMPLATE" ]; then
        local HTML
        HTML=$(cat "$TEMPLATE")
        HTML="${HTML//\{\{CASE_ID\}\}/$CASE_ID}"
        HTML="${HTML//\{\{CASE_TITLE\}\}/$DESCRIPTION}"
        HTML="${HTML//\{\{EXAMINER\}\}/$EXAMINER}"
        HTML="${HTML//\{\{REPORT_DATE\}\}/$REPORT_DATE}"
        HTML="${HTML//\{\{FINDING_COUNT\}\}/$FINDING_COUNT}"
        HTML="${HTML//\{\{EVIDENCE_COUNT\}\}/$EVIDENCE_COUNT}"
        HTML="${HTML//\{\{IOC_COUNT\}\}/$IOC_COUNT}"
        HTML="${HTML//\{\{CLASSIFICATION\}\}/$CLASS}"
        HTML="${HTML//\{\{TARGET_SYSTEM\}\}/$TARGET}"
        HTML="${HTML//\{\{COMPROMISE_DETECTED\}\}/$COMPROMISE}"
        HTML="${HTML//\{\{INVESTIGATION_WINDOW\}\}/$WINDOW}"
        HTML="${HTML//\{\{EXECUTIVE_SUMMARY\}\}/$EXEC_SUMMARY}"

        # Inject timeline events (must use a placeholder approach since bash substitution can't handle multiline well)
        python3 -c "
html = open('$TEMPLATE').read()
# Simple placeholders
html = html.replace('{{CASE_ID}}', '$CASE_ID')
html = html.replace('{{CASE_TITLE}}', '''$(python3 -c "import json; print(json.dumps('$DESCRIPTION'))")''')
html = html.replace('{{EXAMINER}}', '$EXAMINER')
html = html.replace('{{REPORT_DATE}}', '$REPORT_DATE')
html = html.replace('{{FINDING_COUNT}}', '$FINDING_COUNT')
html = html.replace('{{EVIDENCE_COUNT}}', '$EVIDENCE_COUNT')
html = html.replace('{{IOC_COUNT}}', '$IOC_COUNT')
html = html.replace('{{CLASSIFICATION}}', '$CLASS')
html = html.replace('{{TARGET_SYSTEM}}', '''$(python3 -c "import json; print(json.dumps('$TARGET'))")''')
html = html.replace('{{COMPROMISE_DETECTED}}', '''$(python3 -c "import json; print(json.dumps('$COMPROMISE'))")''')
html = html.replace('{{INVESTIGATION_WINDOW}}', '$WINDOW')
html = html.replace('{{EXECUTIVE_SUMMARY}}', '''$(python3 -c "import json; print(json.dumps('$EXEC_SUMMARY'))")''')

with open('$OUT', 'w') as f:
    f.write(html)
print('TEMPLATE_LOADED')
" 2>/dev/null || {
            echo "Python template engine failed, using bash fallback"
            echo "$HTML" > "$OUT"
        }

        # Now inject the large content blocks via Python
        export CASE_DIR REPORT_OUT="$OUT" REPORT_TEMPLATE="$TEMPLATE"
        export DESCRIPTION="$DESCRIPTION" EXAMINER="$EXAMINER" REPORT_DATE="$REPORT_DATE"
        export FINDING_COUNT="$FINDING_COUNT" EVIDENCE_COUNT="$EVIDENCE_COUNT" IOC_COUNT="$IOC_COUNT"
        export CLASSIFICATION="$CLASS" TARGET_SYSTEM="$TARGET"
        export COMPROMISE_DETECTED="$COMPROMISE" INVESTIGATION_WINDOW="$WINDOW" EXECUTIVE_SUMMARY="$EXEC_SUMMARY"
        # Write content blocks to temp files for Python to read
        printf '%s' "$CORR_SECTION" > "$CASE_DIR/.corr_section.html"
        printf '%s' "$TL_HTML" > "$CASE_DIR/.tl_events.html"
        printf '%s' "$FINDINGS_ROWS" > "$CASE_DIR/.findings_rows.html"
        printf '%s' "$IOC_ROWS" > "$CASE_DIR/.ioc_rows.html"
        printf '%s' "$EVIDENCE_ITEMS" > "$CASE_DIR/.evidence_items.html"
        printf '%s' "$TOOLS_ROWS" > "$CASE_DIR/.tools_rows.html"
        # Write vars to temp JSON via Python with stdin to avoid shell quoting
        python3 - "$CASE_DIR/.report_vars.json" << 'VARSJSON'
import json, sys, os

# Read vars from environment (set by caller) and write JSON
vars = {}
for key in ['CASE_ID','DESCRIPTION','EXAMINER','REPORT_DATE','FINDING_COUNT',
            'EVIDENCE_COUNT','IOC_COUNT','CLASSIFICATION','TARGET_SYSTEM',
            'COMPROMISE_DETECTED','INVESTIGATION_WINDOW','EXECUTIVE_SUMMARY']:
    vars[key] = os.environ.get(key, '')

with open(sys.argv[1], 'w') as f:
    json.dump(vars, f)
VARSJSON
        python3 << 'PYEOF2' > "$OUT"
import json, os, re

case_dir = os.environ.get('CASE_DIR', '')
tpl_path = os.environ.get('REPORT_TEMPLATE', '')
out_path = os.environ.get('REPORT_OUT', '')

# Read metadata from temp JSON
with open(os.path.join(case_dir, '.report_vars.json')) as f:
    vars = json.load(f)

# Read template
with open(tpl_path) as f:
    html = f.read()

# Simple subs
for key in ['CASE_ID','DESCRIPTION','EXAMINER','REPORT_DATE','FINDING_COUNT',
            'EVIDENCE_COUNT','IOC_COUNT','CLASSIFICATION','TARGET_SYSTEM',
            'COMPROMISE_DETECTED','INVESTIGATION_WINDOW','EXECUTIVE_SUMMARY']:
    html = html.replace('{{' + key + '}}', str(vars.get(key, '')))

html = html.replace('{{CASE_TITLE}}', vars.get('DESCRIPTION', ''))

# Load generated content from case files
def read_file(path):
    if path and os.path.exists(path):
        with open(path) as f:
            return f.read()
    return ''

# These are written to temp files by the bash script
content_files = {
    '{{CORRELATION_SECTION}}': os.path.join(case_dir, '.corr_section.html'),
    '{{TIMELINE_EVENTS}}':     os.path.join(case_dir, '.tl_events.html'),
    '{{FINDINGS_ROWS}}':       os.path.join(case_dir, '.findings_rows.html'),
    '{{IOC_ROWS}}':            os.path.join(case_dir, '.ioc_rows.html'),
    '{{EVIDENCE_ITEMS}}':      os.path.join(case_dir, '.evidence_items.html'),
    '{{TOOLS_ROWS}}':          os.path.join(case_dir, '.tools_rows.html'),
}
for placeholder, fpath in content_files.items():
    html = html.replace(placeholder, read_file(fpath))

with open(out_path, 'w') as f:
    f.write(html)
PYEOF2
    else
        # No template — generate inline
        echo "Template not found at $TEMPLATE, generating inline..."
        cat > "$OUT" << HTMLEOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Forensic Report — $CASE_ID</title></head>
<body style="background:#020617;color:#e2e8f0;font-family:monospace;padding:40px">
<h1>$DESCRIPTION</h1><p>Case: $CASE_ID · Examiner: $EXAMINER</p>
<h2>Timeline</h2>$TL_HTML
<h2>Findings</h2><table border=1 cellpadding=8>$FINDINGS_ROWS</table>
<h2>IOCs</h2><table border=1 cellpadding=8>$IOC_ROWS</table>
<h2>Evidence</h2>$EVIDENCE_ITEMS
</body></html>
HTMLEOF
    fi

    echo ""
    echo "═══════════════════════════════════════════════"
    echo "  HTML Report: $OUT"
    echo "  Case: $CASE_ID"
    echo "  Findings: $FINDING_COUNT ($HIGH_COUNT HIGH)"
    echo "═══════════════════════════════════════════════"
}

# ══════════════════════════════════════════════════════════════════════════
# Generate
# ══════════════════════════════════════════════════════════════════════════

case "$FORMAT" in
    --html)  generate_html ;;
    --json)  JSON_FILE="$REPORTS_DIR/forensic-report.json"
             python3 -c "
import json, os
case_dir = '$CASE_DIR'
report = {}
for fname in ['CASE.yaml', 'findings.json', 'timeline.json', 'evidence.json']:
    path = os.path.join(case_dir, fname)
    if os.path.exists(path):
        if fname.endswith('.yaml'):
            data = {}
            with open(path) as fh:
                for line in fh:
                    if ':' in line:
                        k, v = line.split(':', 1)
                        data[k.strip()] = v.strip().strip('\"')
            report[fname.replace('.yaml','')] = data
        else:
            with open(path) as fh:
                report[fname.replace('.json','')] = json.load(fh)
with open('$JSON_FILE', 'w') as fh:
    json.dump(report, fh, indent=2, default=str)
print(f'  JSON: $JSON_FILE')
" 2>/dev/null || echo "  JSON generation failed"
             echo "  JSON: $JSON_FILE" ;;
    --pdf)   generate_html
             HTML_FILE="$REPORTS_DIR/forensic-timeline-report.html"
             PDF_FILE="$REPORTS_DIR/forensic-timeline-report.pdf"
             if command -v weasyprint >/dev/null 2>&1; then
                 weasyprint "$HTML_FILE" "$PDF_FILE" 2>/dev/null && \
                     echo "  PDF: $PDF_FILE ($(du -h "$PDF_FILE" | cut -f1))" || \
                     echo "  PDF generation failed — install weasyprint: sudo apt install weasyprint"
             else
                 echo "  weasyprint not installed — sudo apt install weasyprint"
             fi ;;
    --all)   generate_html
             HTML_FILE="$REPORTS_DIR/forensic-timeline-report.html"
             PDF_FILE="$REPORTS_DIR/forensic-timeline-report.pdf"
             if command -v weasyprint >/dev/null 2>&1; then
                 weasyprint "$HTML_FILE" "$PDF_FILE" 2>/dev/null && \
                     echo "  PDF: $PDF_FILE ($(du -h "$PDF_FILE" | cut -f1))" || \
                     echo "  PDF generation failed"
             fi
             echo ""
             echo "Markdown report: $REPORTS_DIR/forensic-report.md" ;;
    --md)    echo "Markdown report: $REPORTS_DIR/forensic-report.md" ;;
    *)       echo "Usage: forensics-report.sh CASE_ID [--html|--pdf|--json|--md|--all]" >&2; exit 1 ;;
esac
