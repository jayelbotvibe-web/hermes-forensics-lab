---

## Appendix: MFT Analysis Workflow

# MFT Analysis

## When to Use
- Analyzing NTFS Master File Table ($MFT) from a disk image
- Timeline reconstruction from $STANDARD_INFORMATION and $FILE_NAME timestamps
- Detecting timestomping (SI vs FN timestamp mismatch)
- Finding Alternate Data Streams (ADS)

## Pre-flight
1. Read $FORENSICS_HOME/tools/tool-catalog.yaml — note: analyzeMFT primary, MFTECmd pending
2. Docker image: forensics-mft-tools:1.2.0.0

## Workflow

### Step 1: Parse MFT
```bash
docker run --rm \
  -v $FORENSICS_HOME/cases/CASE_ID/evidence:/evidence:ro \
  -v $FORENSICS_HOME/cases/CASE_ID/raw:/output \
  forensics-mft-tools:1.2.0.0 \
  python3 -m analyzemft -f /evidence/MFT_FILE -o /output/analyzemft.csv
```

### Step 2: Extract key columns
Focus on: Record Number, File Name, Parent Path, SI Modified, SI Accessed, SI Created, SI Entry Modified, FN Created, FN Modified, Is Directory, In Use

### Step 3: Detect timestomping
Compare SI (Standard Information) timestamps vs FN (File Name) timestamps. 
SI timestamps are trivially modified by attackers. FN timestamps are harder to forge.
Large discrepancies = possible timestomping.

### Step 4: Find suspicious files
- Executables in temp directories
- Files with future timestamps
- Files with timestamps before volume creation
- ADS entries (filename contains ":")
- Recently deleted files (In Use = False)

### Step 5: Create findings
For each suspicious file: record full path, SI/FN timestamps, flags, and interpretation.

## Cross-Validation
For critical MFT findings:
1. Cross-reference with event logs (Event ID 4688 for process creation)
2. Cross-reference with registry (UserAssist, RecentDocs, Shimcache)
3. When MFTECmd becomes available: run as secondary parser for comparison

## Pitfalls
- $MFT is often fragmented — verify the extracted MFT is complete
- $STANDARD_INFORMATION timestamps are unreliable (timestomping)
- Large MFTs (>100MB) consume significant memory in Docker
- analyzeMFT may not parse all $STANDARD_INFORMATION flags on Win11 24H2
