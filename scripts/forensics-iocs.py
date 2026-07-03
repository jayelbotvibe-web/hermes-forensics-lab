#!/usr/bin/env python3
"""
forensics-iocs.py — Extract IOCs from findings.json and export in MISP + STIX 2.1 format.
Usage: python3 forensics-iocs.py CASE_DIR [--misp|--stix|--both]
Output: case/reports/iocs.json (MISP) and/or case/reports/iocs.stix.json (STIX 2.1)
"""
import json
import re
import sys
import os
from datetime import datetime, timezone


def extract_iocs(findings):
    """Extract IOCs from findings array. Returns list of dicts."""
    iocs = []

    for f in findings:
        fid = f.get("id", "?")
        text = f.get("finding", "") + " " + f.get("title", "")
        title = f.get("title", "")

        # IP addresses
        for ip in re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", text):
            if ip not in ("0.0.0.0", "127.0.0.1", "255.255.255.255"):
                iocs.append({"type": "ip-dst", "value": ip, "category": "Network indicator", "finding_id": fid, "finding": title})

        # SHA-256 hashes
        for h in re.findall(r"\b[a-f0-9]{64}\b", text):
            iocs.append({"type": "sha256", "value": h, "category": "File hash", "finding_id": fid, "finding": title})

        # MD5 hashes
        for h in re.findall(r"\b[a-f0-9]{32}\b", text):
            iocs.append({"type": "md5", "value": h, "category": "File hash", "finding_id": fid, "finding": title})

        # Domains
        for d in re.findall(r"\b[a-zA-Z0-9.-]+\.(?:com|org|net|io|do|gov|mil)\b", text):
            if not d.startswith("0.") and len(d) > 6:
                iocs.append({"type": "domain", "value": d, "category": "C2 / phishing domain", "finding_id": fid, "finding": title})

        # Email addresses
        for em in re.findall(r"\b[\w.-]+@[\w.-]+\.\w+\b", text):
            iocs.append({"type": "email-src", "value": em, "category": "Phishing address", "finding_id": fid, "finding": title})

        # File paths (Windows)
        for fp in re.findall(r"[A-Z]:\\[^\s,;]+\.exe", text):
            iocs.append({"type": "filename", "value": fp, "category": "Malware path", "finding_id": fid, "finding": title})

    # Deduplicate by value
    seen = set()
    unique = []
    for ioc in iocs:
        if ioc["value"] not in seen:
            seen.add(ioc["value"])
            unique.append(ioc)

    return unique


def to_misp(iocs, case_id, description):
    """Convert IOCs to MISP event JSON format."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")

    attributes = []
    for ioc in iocs:
        misp_type = {
            "ip-dst": "ip-dst",
            "sha256": "sha256",
            "md5": "md5",
            "domain": "domain",
            "email-src": "email-src",
            "filename": "filename",
        }.get(ioc["type"], "text")

        attributes.append({
            "type": misp_type,
            "category": "Network activity" if ioc["type"] in ("ip-dst", "domain") else
                       "Payload delivery" if ioc["type"] in ("sha256", "md5", "filename") else
                       "External analysis",
            "value": ioc["value"],
            "comment": f"{ioc['finding']} [{ioc['finding_id']}]",
            "to_ids": True,
        })

    event = {
        "Event": {
            "info": f"Forensic Investigation: {description}",
            "date": now[:10],
            "threat_level_id": "3",  # High
            "published": False,
            "analysis": "1",  # Ongoing
            "Attribute": attributes,
            "Tag": [{"name": f"case:{case_id}"}, {"name": "source:hermes-forensics"}],
        }
    }

    return event


def to_stix(iocs, case_id, description):
    """Convert IOCs to STIX 2.1 bundle format."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")

    objects = []
    indicators = []

    for ioc in iocs:
        stix_type = {
            "ip-dst": "ipv4-addr",
            "sha256": "file",
            "md5": "file",
            "domain": "domain-name",
            "email-src": "email-addr",
            "filename": "file",
        }.get(ioc["type"], "x-unknown")

        clean = ioc['value'][:32].replace('.','').replace(':','').replace('\\','')
        obj_id = f"{stix_type}--{clean}"

        if stix_type == "ipv4-addr":
            obj = {"type": "ipv4-addr", "spec_version": "2.1", "id": obj_id, "value": ioc["value"]}
        elif stix_type == "domain-name":
            obj = {"type": "domain-name", "spec_version": "2.1", "id": obj_id, "value": ioc["value"]}
        elif stix_type == "file":
            if ioc["type"] == "filename":
                obj = {"type": "file", "spec_version": "2.1", "id": obj_id, "name": ioc["value"]}
            else:
                hashes = {}
                if ioc["type"] == "sha256":
                    hashes["SHA-256"] = ioc["value"]
                elif ioc["type"] == "md5":
                    hashes["MD5"] = ioc["value"]
                obj = {"type": "file", "spec_version": "2.1", "id": obj_id, "hashes": hashes}
        elif stix_type == "email-addr":
            obj = {"type": "email-addr", "spec_version": "2.1", "id": obj_id, "value": ioc["value"]}
        else:
            obj = {"type": stix_type, "spec_version": "2.1", "id": obj_id, "value": ioc["value"]}

        objects.append(obj)

        # Create an Indicator for each IOC
        indicator = {
            "type": "indicator",
            "spec_version": "2.1",
            "id": f"indicator--{ioc['value'][:32]}",
            "created": now,
            "modified": now,
            "name": f"IOC: {ioc['value'][:60]}",
            "description": f"{ioc['finding']} [{ioc['finding_id']}]",
            "pattern": f"[{stix_type}:value = '{ioc['value']}']",
            "pattern_type": "stix",
            "valid_from": now,
            "indicator_types": ["malicious-activity"],
        }
        indicators.append(indicator)

    bundle = {
        "type": "bundle",
        "id": f"bundle--{case_id}",
        "objects": objects + indicators + [
            {
                "type": "identity",
                "spec_version": "2.1",
                "id": "identity--hermes-forensics",
                "name": "Hermes Forensics Agent",
                "identity_class": "system",
            },
            {
                "type": "report",
                "spec_version": "2.1",
                "id": f"report--{case_id}",
                "created": now,
                "modified": now,
                "name": f"Forensic Investigation: {description}",
                "description": f"Case {case_id}. Generated by Hermes Forensics Agent.",
                "report_types": ["investigation"],
                "object_refs": [ind["id"] for ind in indicators],
                "published": now,
            },
        ],
    }

    return bundle


def main():
    if len(sys.argv) < 2:
        print("Usage: forensics-iocs.py CASE_DIR [--misp|--stix|--both]", file=sys.stderr)
        sys.exit(1)

    case_dir = sys.argv[1]
    fmt = sys.argv[2] if len(sys.argv) > 2 else "--both"

    # Load findings
    findings_path = os.path.join(case_dir, "findings.json")
    case_yaml_path = os.path.join(case_dir, "CASE.yaml")

    if not os.path.exists(findings_path):
        print(f"ERROR: findings.json not found at {findings_path}", file=sys.stderr)
        sys.exit(1)

    with open(findings_path) as f:
        findings = json.load(f)

    # Get case metadata
    case_id = os.path.basename(case_dir.rstrip("/"))
    description = case_id
    if os.path.exists(case_yaml_path):
        with open(case_yaml_path) as f:
            for line in f:
                if line.startswith("description:"):
                    description = line.split(":", 1)[1].strip().strip('"')
                    break

    # Extract IOCs
    iocs = extract_iocs(findings)
    print(f"Extracted {len(iocs)} unique IOCs from {len(findings)} findings")

    reports_dir = os.path.join(case_dir, "reports")
    os.makedirs(reports_dir, exist_ok=True)

    # MISP export
    if fmt in ("--misp", "--both"):
        misp_event = to_misp(iocs, case_id, description)
        misp_path = os.path.join(reports_dir, "iocs.json")
        with open(misp_path, "w") as f:
            json.dump(misp_event, f, indent=2)
        print(f"  MISP: {misp_path} ({len(misp_event['Event']['Attribute'])} attributes)")

    # STIX export
    if fmt in ("--stix", "--both"):
        stix_bundle = to_stix(iocs, case_id, description)
        stix_path = os.path.join(reports_dir, "iocs.stix.json")
        with open(stix_path, "w") as f:
            json.dump(stix_bundle, f, indent=2)
        print(f"  STIX: {stix_path} ({len(stix_bundle['objects'])} objects)")


if __name__ == "__main__":
    main()
