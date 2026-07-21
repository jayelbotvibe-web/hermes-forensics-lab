#!/usr/bin/env python3
"""
encyclopedia-generate.py — Generate SKILL.md from structured YAML entries.

The output is the concatenation of two things:
  1. the generated body, built from encyclopedia/entries/*.yaml
  2. the hand-written appendices in encyclopedia/appendices/*.md, appended
     verbatim in sorted filename order (see appendices/README.md)

Run: python3 encyclopedia/generate.py           # write SKILL.md
     python3 encyclopedia/generate.py --check   # verify only, write nothing
"""
import argparse
import difflib
import re
import sys
from pathlib import Path

import yaml

ENTRIES_DIR = Path(__file__).parent / "entries"
APPENDICES_DIR = Path(__file__).parent / "appendices"
ALLOWLIST_FILE = Path(__file__).parent / "mitre-allowlist.txt"
DEFAULT_OUTPUT_PATH = (
    Path(__file__).parent.parent / "skills" / "forensic-artifacts" / "SKILL.md"
)

# A mitre_attack value may carry a human-readable annotation, e.g.
# "T1571 (Non-Standard Port)". The annotation is rendered as-is but only the
# bare technique ID is validated against the allowlist.
MITRE_ID_RE = re.compile(r"^(\S+?)(?:\s+\([^()]*\))?$")

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
            match = MITRE_ID_RE.match(mid)
            if not match:
                errors.append(
                    f"  MALFORMED MITRE ID: {mid} in entry '{entry['title']}'"
                )
                continue
            if match.group(1) not in allowlist:
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


def load_appendices():
    """Hand-written markdown appended verbatim after the generated body.

    Files are read in sorted filename order (numeric prefixes make that order
    explicit). README.md documents the directory itself and is not content.
    """
    if not APPENDICES_DIR.is_dir():
        return []
    appendices = []
    for md_file in sorted(APPENDICES_DIR.glob("*.md")):
        if md_file.name.lower() == "readme.md":
            continue
        appendices.append((md_file, md_file.read_text()))
    return appendices


def assemble(body, appendices):
    """Join the generated body and the appendices with one blank line between."""
    parts = [body] + [text for _, text in appendices]
    return "\n".join(p.rstrip("\n") + "\n" for p in parts)


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


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        prog="generate.py",
        description=(
            "Generate skills/forensic-artifacts/SKILL.md from "
            "encyclopedia/entries/*.yaml plus the hand-written "
            "encyclopedia/appendices/*.md."
        ),
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help=(
            "Generate in memory and compare against the existing output file. "
            "Prints a unified diff and exits 1 if they differ, exits 0 if "
            "identical. Writes nothing."
        ),
    )
    parser.add_argument(
        "--output",
        metavar="PATH",
        type=Path,
        default=DEFAULT_OUTPUT_PATH,
        help=f"Destination path (default: {DEFAULT_OUTPUT_PATH}).",
    )
    # parse_args (not parse_known_args) rejects unknown arguments with exit 2.
    return parser.parse_args(argv)


def build(entries):
    appendices = load_appendices()
    return assemble(generate_markdown(entries), appendices), appendices


def main(argv=None):
    args = parse_args(argv)

    allowlist = load_allowlist()
    entries = load_entries()

    if not entries:
        print("ERROR: No YAML entries found in encyclopedia/entries/", file=sys.stderr)
        return 1

    errors = validate_mitre_ids(entries, allowlist)
    if errors:
        print("MITRE ATT&CK validation errors:", file=sys.stderr)
        for e in errors:
            print(e, file=sys.stderr)
        return 1

    md, appendices = build(entries)
    categories = len(set(e["category"] for e in entries))

    if args.check:
        if not args.output.exists():
            print(f"CHECK FAILED: {args.output} does not exist.", file=sys.stderr)
            return 1
        existing = args.output.read_text()
        if existing == md:
            print(f"OK: {args.output} is up to date.")
            print(
                f"  {len(entries)} entries, {categories} categories, "
                f"{len(appendices)} appendices"
            )
            return 0
        diff = difflib.unified_diff(
            existing.splitlines(keepends=True),
            md.splitlines(keepends=True),
            fromfile=f"{args.output} (on disk)",
            tofile=f"{args.output} (regenerated)",
        )
        sys.stdout.writelines(diff)
        print(
            f"\nCHECK FAILED: {args.output} is out of date. "
            f"Run: python3 {Path(__file__).name}",
            file=sys.stderr,
        )
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(md)

    print(f"Wrote {args.output}")
    print(f"  {len(md.splitlines())} lines, {len(md)} bytes")
    print(f"  {len(entries)} generated entries across {categories} categories")
    print(f"  All MITRE ATT&CK IDs validated against {ALLOWLIST_FILE.name}")
    if appendices:
        print(f"  {len(appendices)} hand-written appendices appended verbatim:")
        for path, text in appendices:
            print(f"    - {path.name} ({len(text.splitlines())} lines)")
    else:
        print(f"  No appendices found in {APPENDICES_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
