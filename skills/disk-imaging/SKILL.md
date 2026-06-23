---
name: disk-imaging
description: "Forensic disk acquisition and verification — create verified images with dc3dd/ddrescue"
version: 1.0.0
category: forensics
---

# Disk Imaging

## When to Use
- Creating a forensic image of a disk, partition, or removable media
- Verifying an existing image's integrity
- Converting between image formats (raw, E01, AFF)

## Pre-flight
1. Identify source: `bash /home/niel/forensics/scripts/sift-exec.sh "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL"`
2. Verify free space: `df -h /home/niel/forensics/cases/`
3. Read /home/niel/forensics/tools/tool-catalog.yaml for dc3dd known issues
4. Confirm NOT mounted: `bash /home/niel/forensics/scripts/sift-exec.sh "mount | grep DEVICE_NAME"`

## Workflow

### Step 1: Hash source (pre-image)
```bash
bash /home/niel/forensics/scripts/sift-exec.sh "sudo hashdeep -c sha256 DEVICE > /cases/CASE_ID/raw/source-hash.txt"
```

### Step 2: Create image (dc3dd primary)
```bash
bash /home/niel/forensics/scripts/sift-exec.sh "sudo dc3dd if=DEVICE of=/cases/CASE_ID/evidence/IMAGE_NAME.raw hash=sha256 log=/cases/CASE_ID/raw/dc3dd.log"
```

### Step 3: If dc3dd fails, fallback to ddrescue
```bash
bash /home/niel/forensics/scripts/sift-exec.sh "sudo ddrescue -f DEVICE /cases/CASE_ID/evidence/IMAGE_NAME.raw /cases/CASE_ID/raw/ddrescue.log"
```

### Step 4: Verify image hash matches source
Compare source-hash.txt vs image hash.

### Step 5: Set read-only
```bash
chmod 444 /home/niel/forensics/cases/CASE_ID/evidence/IMAGE_NAME.raw
```

### Step 6: Register in evidence.json

## Pitfalls
- Kernel I/O scheduler: dc3dd block size may drift on 6.x+ kernels — ALWAYS verify hash
- SSD TRIM: SSDs return zeros for trimmed blocks — image immediately after seizure
- USB disconnect: always verify hash post-image
- NEVER image a mounted filesystem — writes happen during imaging
- Write-blocker: for evidentiary imaging, always use hardware write-blocker
