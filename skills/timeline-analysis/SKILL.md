---
name: timeline-analysis
description: "Super timeline generation with plaso — comprehensive event timeline across all artifacts"
version: 1.0.0
category: forensics
---

# Timeline Analysis

## When to Use
- Comprehensive timeline across all evidence artifacts
- Correlating events from disk, registry, event logs, memory
- Identifying attack sequence and dwell time

## Pre-flight
1. Run session canary — plaso is MEDIUM stability (fragile dependency chain)
2. Fallback: if plaso canary fails, use sleuthkit mactime (filesystem-forensics skill)
3. Docker image: forensics-plaso:20240512

## Workflow

### Step 1: Create super timeline
```bash
docker run --rm \
  -v $FORENSICS_HOME/cases/CASE_ID:/evidence:ro \
  -v $FORENSICS_HOME/cases/CASE_ID/raw:/output \
  forensics-plaso:20240512 \
  log2timeline.py --storage-file /output/timeline.plaso /evidence/evidence/FILES
```

### Step 2: Filter and export
```bash
# Export as CSV for analysis
docker run --rm \
  -v $FORENSICS_HOME/cases/CASE_ID/raw:/data \
  forensics-plaso:20240512 \
  psort.py -o l2tcsv /data/timeline.plaso > /data/timeline.csv
```

### Step 3: Analyze timeline
Focus on:
- First evidence of compromise (earliest attacker activity)
- Gap between compromise and detection (dwell time)
- Sequence of lateral movement
- Data exfiltration timeline
- Tool execution timeline (prefetch, Shimcache, UserAssist)

### Step 4: Create findings
Use timeline to establish:
- Initial access time window
- Lateral movement sequence
- Data exfiltration window
- Timeline of attacker tools executed

## Pitfalls
- Plaso dependency chain is fragile — if it fails, use mactime via sleuthkit
- Large evidence sets: timeline generation can take hours — warn user
- Timezone handling: verify plaso detected the correct timezone
- Not all artifacts have reliable timestamps (SI vs FN, log truncation)
