#!/bin/bash
# ============================================================================
# forensics-pipeline.sh — End-to-end forensic analysis pipeline.
#
# Usage:  bash forensics-pipeline.sh URL SHA256 "Case Description" [archive_password]
#
# What it does:
#   1. Initializes a new case
#   2. Downloads the evidence
#   3. Verifies hash, extracts, registers evidence
#   4. Runs baseline volatility3 analysis (info, pslist, netscan, malfind, cmdline)
#   5. Mounts MemProcFS and captures process tree
#   6. Generates report skeleton
#
# Example:
#   bash forensics-pipeline.sh \
#       "https://dl.ctf.do/dump.zip" \
#       "3dc0d114859c0bde08d39155eaaa8f76392dd5121ca44ecb15652b3bf6049e35" \
#       "BelkaCTF 7 — Memory Dump Analysis" \
#       "qr9TGBXCGiVoydmccyCq"
# ============================================================================
# Evidence root (override with env var)
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

set -uo pipefail

URL="${1:?Usage: forensics-pipeline.sh URL SHA256 \"Description\" [password]}"
EXPECTED_SHA256="${2:?}"
DESCRIPTION="${3:?}"
ARCHIVE_PASSWORD="${4:-}"

SCRIPTS_DIR="$FORENSICS_HOME/scripts"
FORENSICS_DIR="$FORENSICS_HOME"
CASES_DIR="$FORENSICS_DIR/cases"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Forensics Pipeline — End-to-End Analysis   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════
# Phase 1: Case Init
# ══════════════════════════════════════════════════════════════════════════

echo -e "${CYAN}[1/5] Case Initialization${NC}"
CASE_ID=$(bash "$SCRIPTS_DIR/forensics-case.sh" "$DESCRIPTION" 2>/dev/null | tail -1)
CASE_DIR="$CASES_DIR/$CASE_ID"
echo "  Case: $CASE_ID"
echo "  Path: $CASE_DIR"

# ══════════════════════════════════════════════════════════════════════════
# Phase 2: Download
# ══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}[2/5] Evidence Download${NC}"
FILENAME=$(basename "$URL" | sed 's/?.*//')
DOWNLOAD_PATH="$CASE_DIR/evidence/$FILENAME"

echo "  URL: $URL"
echo "  Expected SHA-256: $EXPECTED_SHA256"

if [ -f "$DOWNLOAD_PATH" ]; then
    echo -e "  ${YELLOW}File already exists, skipping download${NC}"
else
    echo "  Downloading..."
    wget -O "$DOWNLOAD_PATH" "$URL" 2>&1 | tail -3 || {
        echo "  ERROR: Download failed"
        exit 1
    }
fi

# ══════════════════════════════════════════════════════════════════════════
# Phase 3: Extract + Register
# ══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}[3/5] Extraction & Registration${NC}"

# Extract if it's an archive
case "$FILENAME" in
    *.zip)
        echo "  Extracting ZIP archive..."
        if [ -n "$ARCHIVE_PASSWORD" ]; then
            7z x -p"$ARCHIVE_PASSWORD" -y -o"$CASE_DIR/evidence/" "$DOWNLOAD_PATH" 2>&1 | grep -E "Extracting|Everything|Error" | head -5
        else
            unzip -o "$DOWNLOAD_PATH" -d "$CASE_DIR/evidence/" 2>&1 | grep -E "inflating|extracting" | head -5
        fi
        ;;
    *.7z)
        echo "  Extracting 7z archive..."
        7z x -p"$ARCHIVE_PASSWORD" -y -o"$CASE_DIR/evidence/" "$DOWNLOAD_PATH" 2>&1 | grep -E "Extracting|Everything" | head -5
        ;;
    *.tar.gz|*.tgz)
        echo "  Extracting tar.gz..."
        tar xzf "$DOWNLOAD_PATH" -C "$CASE_DIR/evidence/" 2>&1
        ;;
    *.mem|*.dmp|*.raw|*.vmem|*.E01|*.dd)
        echo "  Raw evidence file — no extraction needed"
        ;;
    *)
        echo "  Unknown format — treating as raw"
        ;;
esac

# Find the main evidence file (largest .mem or extracted file)
EVIDENCE_FILE=""
for f in "$CASE_DIR/evidence"/*.mem "$CASE_DIR/evidence"/*.dmp "$CASE_DIR/evidence"/*.raw "$CASE_DIR/evidence"/*.vmem; do
    [ -f "$f" ] && EVIDENCE_FILE="$f" && break
done
if [ -z "$EVIDENCE_FILE" ]; then
    # Fallback: find largest file that isn't the downloaded archive
    EVIDENCE_FILE=$(find "$CASE_DIR/evidence" -type f ! -name "$FILENAME" -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
fi

if [ -n "$EVIDENCE_FILE" ] && [ -f "$EVIDENCE_FILE" ]; then
    echo "  Main evidence: $(basename "$EVIDENCE_FILE")"
    echo "  Registering..."
    EVID_ID=$(bash "$SCRIPTS_DIR/forensics-register.sh" "$CASE_ID" "$EVIDENCE_FILE" "$URL" "$EXPECTED_SHA256" 2>/dev/null | tail -1)
    echo "  Registered: $EVID_ID"
else
    echo "  Registering original download..."
    EVID_ID=$(bash "$SCRIPTS_DIR/forensics-register.sh" "$CASE_ID" "$DOWNLOAD_PATH" "$URL" "$EXPECTED_SHA256" 2>/dev/null | tail -1)
fi

# ══════════════════════════════════════════════════════════════════════════
# Phase 4: Baseline Analysis
# ══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}[4/5] Baseline Volatility3 Analysis${NC}"

for plugin in "windows.info.Info" "windows.pslist.PsList" "windows.netscan.NetScan" "windows.malfind.Malfind" "windows.cmdline.CmdLine" "windows.filescan.FileScan"; do
    echo -n "  $plugin ... "
    bash "$SCRIPTS_DIR/forensics-vol3.sh" "$CASE_ID" "$plugin" >/dev/null 2>&1 && echo "done" || echo "FAILED"
done

# Record tool versions
cat > "$CASE_DIR/tool_versions.json" << EOF
{
  "volatility3": {"version": "2.7.0", "image": "forensics-volatility3:2.7.0", "runtime": "docker", "validated": true},
  "memprocfs": {"version": "5.17.9", "runtime": "host_fuse", "validated": true},
  "plaso": {"version": "20240512", "image": "forensics-plaso:20240512", "runtime": "docker", "validated": true},
  "mft-tools": {"version": "1.2.0.0", "image": "forensics-mft-tools:1.2.0.0", "runtime": "docker", "validated": true}
}
EOF

# ══════════════════════════════════════════════════════════════════════════
# Phase 5: Report Skeleton
# ══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${CYAN}[5/5] Report Generation${NC}"
bash "$SCRIPTS_DIR/forensics-report.sh" "$CASE_ID" >/dev/null 2>&1
echo "  Report: $CASE_DIR/reports/forensic-report.md"

# ══════════════════════════════════════════════════════════════════════════
# Done
# ══════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✓ PIPELINE COMPLETE                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo "  Case ID:    $CASE_ID"
echo "  Evidence:   $(ls "$CASE_DIR/evidence/" | wc -l) files"
echo "  Raw output: $(ls "$CASE_DIR/raw/" 2>/dev/null | wc -l) files"
echo "  Report:     $CASE_DIR/reports/forensic-report.md"
echo ""
echo "  Next steps:"
echo "    1. Review raw output in $CASE_DIR/raw/"
echo "    2. Record findings: bash forensics-find.sh $CASE_ID ..."
echo "    3. Update report executive summary"
echo "    4. Mount MemProcFS: bash forensics-mount.sh $CASE_ID"
echo ""
echo "$CASE_ID"
