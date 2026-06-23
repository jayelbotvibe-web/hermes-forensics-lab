#!/bin/bash
# Session canary — validate ALL forensic tools before investigation
# Run: bash scripts/session-canary.sh
# Exit 0 = all operational, non-zero = some tools degraded
set -uo pipefail

FORENSICS_HOME="${FORENSICS_HOME:-$HOME/forensics}"
SIFT_HOST="${SIFT_HOST:-192.168.88.14}"
SIFT_USER="${SIFT_USER:-sansforensics}"
SIFT_EXEC="ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new ${SIFT_USER}@${SIFT_HOST}"

DEGRADED=()
PASSED=0
FAILED=0

echo "=== Forensics Session Canary ==="
echo "Time: $(date -Iseconds)"
echo "SIFT: ${SIFT_USER}@${SIFT_HOST}"
echo ""

# ── Docker tools (versioned tags, not :latest) ──
declare -A DOCKER_IMAGES=(
  [volatility3]=forensics-volatility3:2.7.0
  [plaso]=forensics-plaso:20240512
  [mft-tools]=forensics-mft-tools:1.2.0.0
)

for tool in "${!DOCKER_IMAGES[@]}"; do
  echo -n "[docker:${tool}] "
  IMAGE="${DOCKER_IMAGES[$tool]}"
  case $tool in
    mft-tools)
      if docker run --rm "$IMAGE" python3 -c "import analyzemft; print('ok')" >/dev/null 2>&1; then
        echo "PASS"; ((PASSED++))
      else
        echo "FAIL — DEGRADED"; ((FAILED++)); DEGRADED+=("$tool")
      fi ;;
    *)
      if docker run --rm "$IMAGE" --help >/dev/null 2>&1; then
        echo "PASS"; ((PASSED++))
      else
        echo "FAIL — DEGRADED"; ((FAILED++)); DEGRADED+=("$tool")
      fi ;;
  esac
done

# ── SIFT VM connectivity ──
echo -n "[sift:connectivity] "
if $SIFT_EXEC "echo OK" >/dev/null 2>&1; then
  echo "PASS"; ((PASSED++))
else
  echo "FAIL — SIFT VM unreachable"; ((FAILED++)); DEGRADED+=("sift-vm")
fi

# ── SIFT native tools ──
if [ ${#DEGRADED[@]} -eq 0 ] || [[ ! " ${DEGRADED[*]} " =~ "sift-vm" ]]; then
  declare -A SIFT_TOOLS=(
    [sleuthkit]="fls -V 2>&1 | head -1"
    [foremost]="foremost -V 2>&1"
    [photorec]="photorec --help 2>&1 | head -1"
    [dc3dd]="dc3dd --version 2>&1"
    [ddrescue]="ddrescue --version 2>&1"
    [regripper]="which regripper 2>&1"
    [hashdeep]="hashdeep -V 2>&1"
    [tshark]="tshark --version 2>&1 | head -1"
  )

  for tool in "${!SIFT_TOOLS[@]}"; do
    echo -n "[sift:${tool}] "
    if $SIFT_EXEC "${SIFT_TOOLS[$tool]}" >/dev/null 2>&1; then
      echo "PASS"; ((PASSED++))
    else
      echo "FAIL — DEGRADED"; ((FAILED++)); DEGRADED+=("$tool")
    fi
  done
fi

echo ""
echo "=== Results: ${PASSED} passed, ${FAILED} failed ==="
if [ ${#DEGRADED[@]} -gt 0 ]; then
  echo "⚠️  DEGRADED: ${DEGRADED[*]}"
  echo "DEGRADED tools are TRIAGE-ONLY — not for evidentiary work."
  exit 1
fi
echo "✓ All tools operational"
exit 0