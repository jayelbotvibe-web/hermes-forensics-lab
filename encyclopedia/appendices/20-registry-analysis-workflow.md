---

## Appendix: Registry Analysis Workflow

# Registry Analysis

## When to Use
- Analyzing Windows registry hives (SYSTEM, SOFTWARE, SAM, NTUSER.DAT, USRCLASS.DAT)
- Detecting persistence mechanisms (Run keys, services, scheduled tasks)
- User activity analysis (UserAssist, RecentDocs, typed URLs)

## Pre-flight
1. Read $FORENSICS_HOME/tools/tool-catalog.yaml — RegRipper 3.0 via SIFT VM
2. Evidence must be registered in evidence.json

## Workflow

### Step 1: Run RegRipper against a hive
```bash
bash $FORENSICS_HOME/scripts/sift-exec.sh "rip -r /cases/CASE_ID/evidence/HIVE_FILE -a > /cases/CASE_ID/raw/regripper.txt"
```

### Step 2: Extract persistence mechanisms
Search output for:
- Run/RunOnce keys: `Software\Microsoft\Windows\CurrentVersion\Run`
- Services: `System\CurrentControlSet\Services`
- Scheduled tasks
- Winlogon/AppInit DLLs
- Browser helper objects

### Step 3: Extract user activity
Search output for:
- UserAssist (GUI program execution history)
- RecentDocs (recently opened files)
- TypedURLs (IE/Edge typed URLs)
- Shellbags (folder access history)

### Step 4: SAM/SECURITY hive analysis
- User accounts and groups (SAM)
- Password policy (SAM)
- Service accounts (SECURITY)

### Step 5: Create findings
For each persistence mechanism: record full key path, value data, tool output, and interpretation.

## Pitfalls
- RegRipper may report "Unknown type" for new Win11 value types
- Deleted registry keys not recoverable from hive alone (need transaction logs too)
- SYSTEM hive requires admin to extract from live system
- RegRipper Perl runtime — ensure SIFT VM has it installed
