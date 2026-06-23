---
name: file-carving
description: "Data recovery and file carving — foremost and photorec for recovering deleted files"
version: 1.0.0
category: forensics
---

# File Carving

## When to Use
- Recovering deleted files from disk images
- Extracting files by file signature (headers/footers)
- Need to run both foremost AND photorec for completeness (different signature databases)

## Pre-flight
1. Read /home/niel/forensics/tools/tool-catalog.yaml
2. Both foremost AND photorec must be run — they use different signature DBs
3. Carving output goes to a subdirectory: /cases/CASE_ID/raw/carved/

## Workflow

### Step 1: Create output directory
```bash
mkdir -p /home/niel/forensics/cases/CASE_ID/raw/carved/{foremost,photorec}
```

### Step 2: Run foremost
```bash
bash /home/niel/forensics/scripts/sift-exec.sh "foremost -i /cases/CASE_ID/evidence/DISK_IMAGE -o /cases/CASE_ID/raw/carved/foremost"
```

### Step 3: Run photorec
```bash
bash /home/niel/forensics/scripts/sift-exec.sh "photorec /log /d /cases/CASE_ID/raw/carved/photorec /cases/CASE_ID/evidence/DISK_IMAGE"
```

### Step 4: Compare results
Both tools use different file signature databases — files found by one may not be found by the other.

### Step 5: Hash recovered files
```bash
bash /home/niel/forensics/scripts/sift-exec.sh "hashdeep -c sha256 -r /cases/CASE_ID/raw/carved/"
```

### Step 6: Create findings
For significant recovered files: filename, format, size, hash, and relevance to case.

## Pitfalls
- NTFS compression: carved files may be incomplete
- File fragmentation: carvers recover the first fragment only
- Large images: carving runs for hours — warn user and use background execution
- False positives: carvers may produce junk files from random byte sequences
- Space requirement: carved output can exceed source image size
