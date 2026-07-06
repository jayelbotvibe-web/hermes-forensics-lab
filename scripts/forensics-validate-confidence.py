#!/usr/bin/env python3
"""
forensics-validate-confidence.py — Machine-checkable confidence tier validator.
Reads a finding and checks: canary status, encyclopedia match, OS version.
Outputs: actual tier vs. claimed tier, flags mismatches.
Usage: python3 forensics-validate-confidence.py CASE_DIR FINDING_ID
"""
import json
import os
import sys


def load_case_data(case_dir):
    """Load all relevant case data."""
    data = {}

    # Findings
    findings_path = os.path.join(case_dir, "findings.json")
    if os.path.exists(findings_path):
        with open(findings_path) as f:
            data["findings"] = json.load(f)

    # Tool versions (canary results)
    tv_path = os.path.join(case_dir, "tool_versions.json")
    if os.path.exists(tv_path):
        with open(tv_path) as f:
            data["tool_versions"] = json.load(f)

    # System profile (OS version)
    sp_path = os.path.join(case_dir, "system_profile.json")
    if os.path.exists(sp_path):
        with open(sp_path) as f:
            data["system_profile"] = json.load(f)

    # CASE.yaml
    case_yaml = os.path.join(case_dir, "CASE.yaml")
    if os.path.exists(case_yaml):
        data["case_yaml"] = {}
        with open(case_yaml) as f:
            for line in f:
                if ":" in line:
                    k, v = line.split(":", 1)
                    data["case_yaml"][k.strip()] = v.strip().strip('"')

    return data


def check_canary(finding, data):
    """Check if the tool used for this finding passed the canary."""
    tv = data.get("tool_versions", {})
    tool_name = finding.get("tool", "").split()[0]  # e.g., "volatility3" from "volatility3 2.7.0"

    # Map tool names to tool_versions keys
    tool_map = {
        "volatility3": ["volatility3"],
        "memprocfs": ["memprocfs"],
        "plaso": ["plaso"],
        "mft-tools": ["mft-tools"],
        "sleuthkit": ["sleuthkit"],
        "foremost": ["foremost"],
        "dc3dd": ["dc3dd"],
        "regripper": ["regripper"],
        "hashdeep": ["hashdeep"],
        "tshark": ["tshark"],
    }

    for key in tool_map.get(tool_name, [tool_name]):
        if key in tv:
            info = tv[key]
            if isinstance(info, dict):
                return info.get("validated", False)
    return None  # Unknown tool or no canary data


def check_os_known(data):
    """Check if OS version is known."""
    sp = data.get("system_profile", {})
    if sp:
        os_name = sp.get("os_name", "") or sp.get("os", "")
        os_version = sp.get("os_version", "") or sp.get("version", "")
        if os_name or os_version:
            return True
    # Fallback: check CASE.yaml
    case = data.get("case_yaml", {})
    return bool(case.get("os") or case.get("target_system"))


def determine_actual_tier(finding, data):
    """Determine the actual confidence tier based on available data."""
    canary_ok = check_canary(finding, data)
    os_known = check_os_known(data)

    # Canary failed → TENTATIVE
    if canary_ok is False:
        return "TENTATIVE", "Canary failed for this tool"

    # Canary unknown → LOW at best
    if canary_ok is None:
        if os_known:
            return "LOW", "Canary status unknown; OS known"
        return "LOW", "Canary status unknown"

    # Canary passed + OS unknown → LOW
    if not os_known:
        return "LOW", "Canary passed; OS version unknown"

    # Canary passed + OS known → MEDIUM or HIGH
    # HIGH requires encyclopedia match — always return MEDIUM by default
    # (encyclopedia match is determined during analysis, not checkable post-hoc without structured data)
    return "MEDIUM", "Canary passed; OS version known"


TIER_ORDER = {"TENTATIVE": 0, "LOW": 1, "MEDIUM": 2, "HIGH": 3}


def main():
    if len(sys.argv) < 2:
        print("Usage: forensics-validate-confidence.py CASE_DIR [FINDING_ID]", file=sys.stderr)
        print("  Without FINDING_ID: validates all findings in the case", file=sys.stderr)
        sys.exit(1)

    case_dir = sys.argv[1]
    target_id = sys.argv[2] if len(sys.argv) > 2 else None

    data = load_case_data(case_dir)
    findings = data.get("findings", [])

    if not findings:
        print("No findings found in case directory")
        sys.exit(1)

    issues = 0
    for f in findings:
        fid = f.get("id", "?")
        if target_id and fid != target_id:
            continue

        claimed = f.get("confidence", "?").upper()
        actual, reason = determine_actual_tier(f, data)

        claimed_order = TIER_ORDER.get(claimed, -1)
        actual_order = TIER_ORDER.get(actual, -1)

        status = "OK"
        if claimed_order > actual_order:
            status = "OVERCONFIDENT"
            issues += 1
        elif claimed != actual:
            status = "LOWER"

        print(f"  {fid}: claimed={claimed} actual={actual} [{status}] — {reason}")

    print(f"\n{len(findings) if not target_id else 1} finding(s) checked, {issues} issue(s)")
    sys.exit(0 if issues == 0 else 1)


if __name__ == "__main__":
    main()
