#!/usr/bin/env python3
"""Generate evidence artifacts appendix HTML from raw tool output files."""
import os, sys, json
from datetime import datetime

CASE_DIR = sys.argv[1] if len(sys.argv) > 1 else "/home/niel/forensics/cases/INC-2026-0624-0001"
RAW_DIR = os.path.join(CASE_DIR, "raw")
OUT = os.path.join(RAW_DIR, "artifacts.html")

files = sorted([f for f in os.listdir(RAW_DIR) if f.endswith(('.csv','.txt','.json')) and os.path.isfile(os.path.join(RAW_DIR, f))])
case_id = os.path.basename(CASE_DIR)

css = """body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f8f9fb; color: #1a1a2e; padding: 24px; max-width: 960px; margin: 0 auto; }
h1 { font-size: 18px; border-bottom: 2px solid #2563eb; padding-bottom: 8px; }
.artifact { background: #fff; border: 1px solid #dde1e6; border-radius: 8px; margin-bottom: 24px; overflow: hidden; }
.artifact-header { background: #f1f5f9; padding: 12px 16px; border-bottom: 1px solid #dde1e6; display: flex; justify-content: space-between; align-items: center; }
.artifact-header .name { font-weight: 700; font-size: 13px; }
.artifact-header .meta { font-size: 10px; color: #6b7280; }
.artifact-body { padding: 16px; overflow-x: auto; }
.artifact-body pre { font-family: 'SF Mono', Consolas, Monaco, monospace; font-size: 10px; line-height: 1.5; margin: 0; white-space: pre-wrap; word-break: break-all; max-height: 400px; overflow-y: auto; background: #f8f9fb; padding: 12px; border-radius: 4px; }
.artifact-body table { width: 100%; border-collapse: collapse; font-size: 10px; }
.artifact-body th { text-align: left; padding: 4px 8px; background: #f1f5f9; border-bottom: 2px solid #c4c9d0; font-size: 9px; color: #6b7280; text-transform: uppercase; }
.artifact-body td { padding: 4px 8px; border-bottom: 1px solid #dde1e6; vertical-align: top; font-size: 10px; }
.section-label { font-size: 9px; text-transform: uppercase; letter-spacing: 2px; color: #2563eb; font-weight: 700; margin-bottom: 4px; }
.footer { text-align: center; font-size: 10px; color: #6b7280; margin-top: 32px; padding-top: 16px; border-top: 1px solid #dde1e6; }"""

html_parts = [
    '<!DOCTYPE html>',
    '<html><head><meta charset="UTF-8"><title>Evidence Artifacts</title>',
    f'<style>{css}</style></head><body>',
    '<div class="section-label">APPENDIX A</div>',
    '<h1>Evidence Artifacts — Raw Tool Output</h1>',
    f'<p style="font-size:12px;color:#6b7280;margin-bottom:24px">Case: {case_id} · {len(files)} artifacts · {datetime.now().isoformat()}</p>'
]

for i, filename in enumerate(files, 1):
    filepath = os.path.join(RAW_DIR, filename)
    try:
        with open(filepath, errors='replace') as f:
            content = f.read()
    except:
        content = "[Error reading file]"
    
    lines = content.count('\n') + 1
    size_kb = os.path.getsize(filepath) / 1024
    tool_name = filename.replace('vol3_', '').rsplit('.', 1)[0].replace('_', ' ')
    
    html_parts.append(f'<div class="artifact">')
    html_parts.append(f'<div class="artifact-header"><span class="name">A{i}. {tool_name}</span><span class="meta">{filename} · {lines:,} lines · {size_kb:.0f} KB</span></div>')
    html_parts.append(f'<div class="artifact-body">')
    
    ext = filename.rsplit('.', 1)[-1] if '.' in filename else ''
    if ext == 'csv' and '\t' in content[:200]:
        rows = content.strip().split('\n')
        if rows:
            html_parts.append('<table>')
            cols = rows[0].split('\t')
            html_parts.append('<tr>' + ''.join(f'<th>{c[:40]}</th>' for c in cols) + '</tr>')
            for row in rows[1:51]:
                cols = row.split('\t')
                html_parts.append('<tr>' + ''.join(f'<td>{c[:200]}</td>' for c in cols) + '</tr>')
            html_parts.append('</table>')
            if len(rows) > 51:
                html_parts.append(f'<p style="font-size:10px;color:#6b7280;margin-top:8px">Showing 50 of {len(rows):,} rows</p>')
    else:
        preview = content[:8000]
        escaped = preview.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
        html_parts.append(f'<pre>{escaped}</pre>')
        if len(content) > 8000:
            html_parts.append('<p style="font-size:10px;color:#6b7280;margin-top:4px">Output truncated — full data in raw file</p>')
    
    html_parts.append('</div></div>')

html_parts.append('<div class="footer"><p>Hermes Forensics Agent · Evidence Artifacts Appendix</p><p>All content is raw tool output — unmodified from original execution. Each artifact is traceable to the findings register.</p></div>')
html_parts.append('</body></html>')

with open(OUT, 'w') as f:
    f.write('\n'.join(html_parts))

print(f"Artifacts appendix: {OUT}")
print(f"  {len(files)} artifacts rendered ({os.path.getsize(OUT):,} bytes)")
for f in files:
    size = os.path.getsize(os.path.join(RAW_DIR, f)) / 1024
    print(f"    {f} ({size:.0f} KB)")
