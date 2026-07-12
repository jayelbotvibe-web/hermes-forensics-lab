# BelkaCTF #7 — sample case (for correlation-pass Step 3)

These three JSON files reconstruct the case behind the repo's shipped sample
report (`reports/samples/belkactf7-data-report.html`). Findings, IOCs, and
timeline events are transcribed from that published report; per-event `source`
tool labels are filled from the repo's documented toolchain (README tool
inventory) so the correlation pass has independent sources to cross-reference.
No findings were invented.

Schema matches the repo exactly:
- findings.json : id, title, confidence, tool, command, evidence_ref, raw_output, finding  (forensics-find.sh)
- timeline.json : id, timestamp, event, source                                              (forensics-report.sh)
- evidence.json : evidence_id, filename, sha256, md5, source, timestamp                      (forensics-register.sh)

Use for the read-only regression check:

    sha256sum sample-case/findings.json
    python3 scripts/forensics-verify.py sample-case
    sha256sum sample-case/findings.json      # must be identical
    head -40 sample-case/correlation-summary.txt

Do NOT commit sample-case/correlation-proposals.json or correlation-summary.txt
(they are per-run output).
