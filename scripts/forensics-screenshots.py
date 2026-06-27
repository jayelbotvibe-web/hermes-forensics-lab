#!/usr/bin/env python3
# Evidence root (override with env var)
FORENSICS_HOME="${FORENSICS_HOME:-$HOME/forensics}"

"""
Generate terminal-style screenshot PNGs from raw tool output files.
Creates case/raw/screenshots/ with artifact-XX.png images.
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

CASE_DIR = sys.argv[1] if len(sys.argv) > 1 else "$FORENSICS_HOME/cases/INC-2026-0624-0001"
RAW_DIR = os.path.join(CASE_DIR, "raw")
SCREENSHOT_DIR = os.path.join(RAW_DIR, "screenshots")
os.makedirs(SCREENSHOT_DIR, exist_ok=True)

# Terminal look: dark background, green-ish text
BG = (18, 18, 24)       # dark terminal
FG = (200, 210, 210)     # light text
ACCENT = (100, 200, 255) # blue for headers
RED = (255, 100, 100)    # for highlights
DIM = (120, 130, 140)    # dim text

FONT_SIZE = 13
LINE_HEIGHT = 18
PADDING = 20
MAX_LINES = 60

# Try to load a monospace font
font = None
for path in ["/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
             "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
             "/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf"]:
    if os.path.exists(path):
        font = ImageFont.truetype(path, FONT_SIZE)
        break
if font is None:
    font = ImageFont.load_default()

def create_screenshot(filename, label, num):
    """Create a terminal-style PNG from a text file."""
    filepath = os.path.join(RAW_DIR, filename)
    
    # Read content
    try:
        with open(filepath, errors='replace') as f:
            content = f.read()
    except:
        return None
    
    lines_raw = content.strip().split('\n')
    total_lines = len(lines_raw)
    
    # Take first MAX_LINES lines for the screenshot
    display_lines = lines_raw[:MAX_LINES]
    
    # Build display lines: header + content
    output_lines = []
    output_lines.append(("header", f"┌─ Artifact {num}: {label}"))
    output_lines.append(("header", f"│  File: {filename}  ·  {total_lines:,} lines  ·  {os.path.getsize(filepath)/1024:.0f} KB"))
    output_lines.append(("header", f"└{'─'*78}"))
    output_lines.append(("spacer", ""))
    
    for line in display_lines:
        # Truncate very long lines
        if len(line) > 140:
            line = line[:137] + "..."
        output_lines.append(("content", line))
    
    if total_lines > MAX_LINES:
        output_lines.append(("dim", f"... ({total_lines - MAX_LINES:,} more lines — see raw file for full output)"))
    
    # Calculate image dimensions
    img_width = max(len(l[1]) for l in output_lines) * 8 + PADDING * 2
    img_width = max(img_width, 800)
    img_width = min(img_width, 1400)
    img_height = len(output_lines) * LINE_HEIGHT + PADDING * 2
    
    img = Image.new('RGB', (img_width, img_height), BG)
    draw = ImageDraw.Draw(img)
    
    y = PADDING
    for line_type, text in output_lines:
        if line_type == "header":
            draw.text((PADDING, y), text, fill=ACCENT, font=font)
        elif line_type == "dim":
            draw.text((PADDING, y), text, fill=DIM, font=font)
        elif line_type == "spacer":
            pass
        else:
            # Color-code important lines
            if any(w in text.lower() for w in ['epxlorer', 'malware', '9920', 'c2', 'established']):
                draw.text((PADDING, y), text, fill=RED, font=font)
            else:
                draw.text((PADDING, y), text, fill=FG, font=font)
        y += LINE_HEIGHT
    
    out_path = os.path.join(SCREENSHOT_DIR, f"artifact-{num:02d}.png")
    img.save(out_path, "PNG", optimize=True)
    return out_path, os.path.getsize(out_path)

# Process all tool output files
files = sorted([f for f in os.listdir(RAW_DIR) 
                if f.endswith(('.csv','.txt','.json')) 
                and os.path.isfile(os.path.join(RAW_DIR, f))])

results = []
for i, filename in enumerate(files, 1):
    tool_name = filename.replace('vol3_', '').replace('windows_', '').rsplit('.', 1)[0].replace('_', ' ')
    print(f"  [{i}/{len(files)}] {filename} ...", end=" ")
    result = create_screenshot(filename, tool_name, i)
    if result:
        path, size = result
        results.append((i, tool_name, filename, path, size))
        print(f"OK ({size//1024}KB)")
    else:
        print("SKIP")

# Generate index.html for the screenshots folder
index_path = os.path.join(SCREENSHOT_DIR, "index.html")
with open(index_path, 'w') as f:
    f.write('''<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Evidence Screenshots</title>
<style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#1a1a2e;color:#e2e8f0;padding:24px;max-width:1000px;margin:0 auto}
h1{color:#60a5fa;border-bottom:2px solid #2563eb;padding-bottom:8px}
.artifact{background:#0f172a;border:1px solid #1e293b;border-radius:8px;margin-bottom:24px;overflow:hidden}
.artifact-header{background:#1e293b;padding:10px 16px;font-size:12px;display:flex;justify-content:space-between}
.artifact-header .label{font-weight:600;color:#93c5fd}
.artifact-header .meta{color:#64748b;font-size:10px}
img{width:100%;display:block;border-top:1px solid #1e293b}
</style></head><body>
<h1>Evidence Screenshots — Raw Tool Output</h1>
<p style="color:#64748b;margin-bottom:24px">Terminal-style captures of tool output. Each screenshot is unmodified raw data rendered as evidence.</p>
''')
    for num, tool_name, filename, path, size in results:
        rel = os.path.basename(path)
        f.write(f'<div class="artifact"><div class="artifact-header"><span class="label">A{num:02d}. {tool_name}</span><span class="meta">{filename} · {size//1024}KB</span></div><img src="{rel}" alt="{tool_name}"></div>\n')
    f.write('</body></html>')

print(f"\n{'='*60}")
print(f"Screenshots: {SCREENSHOT_DIR}")
print(f"  {len(results)} images generated")
total_kb = sum(r[4] for r in results) // 1024
print(f"  Total size: {total_kb}KB")
print(f"  Gallery: {index_path}")
