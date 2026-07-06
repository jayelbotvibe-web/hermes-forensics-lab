#!/usr/bin/env python3
"""
encyclopedia-generate.py — Generate SKILL.md from structured YAML entries.
Run: python3 encyclopedia/generate.py
"""
import yaml
import os
import sys
from pathlib import Path

ENTRIES_DIR = Path(__file__).parent / "entries"
ALLOWLIST_FILE = Path(__file__).parent / "mitre-allowlist.txt"
OUTPUT_PATH = Path(__file__).parent.parent / "skills" / "forensic-artifacts" / "SKILL.md"

CATEGORIES = ["Process", "Network", "Registry", "Filesystem", "MFT", "Memory"]
CATEGORY_DESCRIPTIONS = {
    "Process": "Process anomalies, masquerading, injection, parent-child relationships",
    "Network": "C2 beaconing, unusual ports, data exfiltration, lateral movement, DNS anomalies",
    "Registry": "Persistence mechanisms (Run keys, services, scheduled tasks), user activity, RDP history",
    "Filesystem": "ADS detection, timestomp, hidden files, web shells, Prefetch anomalies, browser download artifacts",
    "MFT": "SI/FN timestamp mismatch, resident data hiding, deleted file recovery, UsnJrnl anomalies",
    "Memory": "Injected code (RWX), unlinked DLLs, malware mutexes, process-network C2 correlation",
}


def load_allowlist():
    ids = set()
    with open(ALLOWLIST_FILE) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                ids.add(line)
    return ids


def validate_mitre_ids(entries, allowlist):
    errors = []
    for entry in entries:
        for mid in entry.get("mitre_attack", []):
            if mid not in allowlist:
                errors.append(
                    f"  INVALID MITRE ID: {mid} in entry '{entry['title']}'"
                )
    return errors


def load_entries():
    entries = []
    for yaml_file in sorted(ENTRIES_DIR.glob("*.yaml")):
        with open(yaml_file) as f:
            raw = f.read()
        title = raw.strip().split("\n")[0].lstrip("# ")
        entry = yaml.safe_load(raw)
        entry["title"] = title
        entry["source_file"] = yaml_file.name
        entries.append(entry)
    return entries


def generate_markdown(entries):
    by_category = {}
    for e in entries:
        cat = e["category"]
        by_category.setdefault(cat, []).append(e)

    lines = []
    lines.append("---")
    lines.append("name: forensic-artifacts")
    lines.append(
        'description: "Forensic artifact interpretation encyclopedia. Auto-generated from structured YAML."'
    )
    lines.append("version: 2.0.0")
    lines.append("category: forensics")
    lines.append("---")
    lines.append("")
    lines.append(
        "> **Auto-generated from structured YAML.** Source: `encyclopedia/entries/*.yaml`."
    )
    lines.append("")
    lines.append("# Forensic Artifacts Encyclopedia")
    lines.append("")
    lines.append(
        "Maps common forensic artifacts to interpretation, attacker behavior, and MITRE ATT&CK techniques."
    )
    lines.append("")
    lines.append("## How to Use")
    lines.append("")
    lines.append(
        "1. Identify the artifact type (Process, Network, Registry, Filesystem, MFT, Memory)"
    )
    lines.append("2. Jump to the corresponding section below")
    lines.append(
        '3. Match the observed artifact against the "What You See" column'
    )
    lines.append("4. Read the interpretation and ATT&CK mapping")
    lines.append("")
    lines.append("## Coverage")
    lines.append("")
    lines.append(
        "| Category | Entries | Example Artifacts |"
    )
    lines.append("|---|---|---|")
    for cat in CATEGORIES:
        count = len(by_category.get(cat, []))
        desc = CATEGORY_DESCRIPTIONS.get(cat, "")
        lines.append(f"| **{cat}** | {count} | {desc} |")
    lines.append("")
    lines.append(
        f"**Total: {len(entries)} entries across {len(by_category)} categories.**"
    )
    lines.append("")

    for cat in CATEGORIES:
        cat_entries = by_category.get(cat, [])
        if not cat_entries:
            continue
        lines.append("---")
        lines.append("")
        lines.append(f"## {cat} Artifacts")
        lines.append("")

        for e in cat_entries:
            lines.append(f"### {e['title']}")
            lines.append("")
            lines.append(f"**What You See**: {e['what_you_see']}")
            lines.append("")
            lines.append(f"**Interpretation**: {e['interpretation']}")
            lines.append("")
            if e.get("mitre_attack"):
                mitre = ", ".join(e["mitre_attack"])
                lines.append(f"**MITRE ATT&CK**: {mitre}")
            else:
                lines.append("**MITRE ATT&CK**: N/A")
            lines.append("")
            lines.append(f"**Confidence**: {e['confidence_rule']}")
            lines.append("")
            lines.append(f"**Next Step**: {e['next_step']}")
            lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("## Cross-Reference: Finding to Next Steps")
    lines.append("")
    lines.append(
        "| Finding Type | Next Phase | Tool Source | Record As |"
    )
    lines.append("|---|---|---|---|")
    refs = [
        ("Process anomaly", "Phase 2: Deep-dive that PID", "volatility3, MemProcFS", "Finding with PID, path, parent PID"),
        ("Typo-squatted name", "Phase 2: Hash comparison, path check", "volatility3, MemProcFS exe/", "Finding + IOC (binary hash, path)"),
        ("Network beacon", "Phase 2: Trace to process, extract IOCs", "netscan, MemProcFS net/", "IOC (IP, domain, port)"),
        ("Registry persistence", "Phase 2: Trace binary, timeline entry", "RegRipper via sift-exec.sh", "Finding + IOC (registry key, binary hash)"),
        ("Timestomp", "Phase 2: File-system timeline", "sleuthkit, plaso via sift-exec.sh", "Finding + timeline event"),
        ("Web shell", "Phase 2: Log analysis, command timeline", "sleuthkit fls", "Finding + IOC (file path, hash)"),
        ("Browser download", "Phase 2: Extract Zone.Identifier, correlate email", "sleuthkit icat, volatility3 filescan", "Finding + IOC (download URL, sender domain)"),
        ("Injected code", "Phase 2: Extract and analyze payload", "volatility3 malfind, MemProcFS VAD", "Finding + IOC (mutex, C2 IP)"),
    ]
    for finding, phase, tools, record in refs:
        lines.append(f"| {finding} | {phase} | {tools} | {record} |")
    lines.append("")

    lines.append("## Pitfalls")
    lines.append("")
    pitfalls = [
        "**Artifact is not Malicious**: An unsigned binary in Temp folder could be a legitimate installer. Always correlate with parent process, network connections, and timeline context before calling it.",
        "**SI/FN mismatch in virtualized apps**: Some application virtualization (App-V, ThinApp) legitimately touches timestamps. Confirm the mismatch aligns with attacker activity window.",
        "**Memory-only artifacts are volatile**: Process injection evidence disappears on reboot. Capture memory dumps FIRST in any investigation sequence.",
        "**Mutex names change between versions**: Rely on mutex patterns (guid-like, specific prefixes) rather than exact strings. Threat intel IOCs go stale within weeks.",
        "**Port numbers are not definitive**: Port 4444 has legitimate uses (Kubernetes, some databases). Always check the actual traffic or process context.",
    ]
    for p in pitfalls:
        lines.append(f"1. {p}")
        lines.append("")

    return "\n".join(lines)


def main():
    allowlist = load_allowlist()
    entries = load_entries()

    if not entries:
        print("ERROR: No YAML entries found in encyclopedia/entries/", file=sys.stderr)
        sys.exit(1)

    errors = validate_mitre_ids(entries, allowlist)
    if errors:
        print("MITRE ATT&CK validation errors:", file=sys.stderr)
        for e in errors:
            print(e, file=sys.stderr)
        sys.exit(1)

    md = generate_markdown(entries)
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        f.write(md)

    print(f"Generated {OUTPUT_PATH}")
    print(f"  {len(entries)} entries across {len(set(e['category'] for e in entries))} categories")
    print(f"  All MITRE ATT&CK IDs validated")


if __name__ == "__main__":
    main()
