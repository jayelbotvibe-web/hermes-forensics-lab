---
name: filesystem-forensics
description: "Filesystem analysis with Sleuth Kit — file listing, inode extraction, timeline generation"
version: 1.0.0
category: forensics
---

# Filesystem Forensics

## When to Use
- Analyzing a disk image for file activity
- Extracting timeline (MACB times) from filesystem metadata
- Recovering deleted files via inode extraction
- Need mactime timeline as fallback when plaso is unavailable

## Pre-flight
1. Evidence must be registered in evidence.json
2. Read $FORENSICS_HOME/tools/tool-catalog.yaml for sleuthkit version
3. Verify SIFT VM is reachable: `bash $FORENSICS_HOME/scripts/sift-exec.sh "echo OK"`

## Workflow

### Step 1: List filesystem
```bash
bash $FORENSICS_HOME/scripts/sift-exec.sh "fls -r -m / /cases/CASE_ID/evidence/IMAGE_FILE"
```

### Step 2: Extract file by inode
```bash
bash $FORENSICS_HOME/scripts/sift-exec.sh "icat /cases/CASE_ID/evidence/IMAGE_FILE INODE_NUMBER"
```

### Step 3: Get file metadata
```bash
bash $FORENSICS_HOME/scripts/sift-exec.sh "istat /cases/CASE_ID/evidence/IMAGE_FILE INODE_NUMBER"
```

### Step 4: Generate body file for timeline
```bash
bash $FORENSICS_HOME/scripts/sift-exec.sh "fls -r -m / /cases/CASE_ID/evidence/IMAGE_FILE > /cases/CASE_ID/raw/bodyfile.txt"
```

### Step 5: Generate mactime timeline
```bash
bash $FORENSICS_HOME/scripts/sift-exec.sh "mactime -b /cases/CASE_ID/raw/bodyfile.txt -d > /cases/CASE_ID/raw/timeline.csv"
```

### Step 6: Create findings
For suspicious files: note timestamps, path, inode, and why suspicious.

## Pitfalls
- fls needs the partition offset for raw images — use `mmls` first to find it
- mactime outputs local time by default — verify timezone
- Deleted files show as (deleted) in fls output — inode may be reused
- NTFS $MFT timestamps have 100ns precision; fls rounds to seconds
