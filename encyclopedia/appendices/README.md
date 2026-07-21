# Encyclopedia Appendices

Files in this directory are **hand-written**. They are *not* generated from
`encyclopedia/entries/*.yaml` and nothing regenerates them.

`encyclopedia/generate.py` reads every `*.md` file here in sorted filename order
and appends it **verbatim** to the end of the generated
`skills/forensic-artifacts/SKILL.md`, after the last generated section
(`## Pitfalls`). The only thing the generator adds is a single blank line
between the generated body and each appendix.

## Adding an appendix

This is the correct place to add narrative / workflow documentation that does
not fit the structured "one artifact, one entry" YAML schema — step-by-step
analysis workflows, tool-specific runbooks, and similar prose.

1. Create a new `NN-slug.md` file here. The numeric prefix makes the ordering
   explicit and stable; leave gaps (10, 20, 30) so files can be inserted later
   without renumbering.
2. Start the file with a `---` horizontal rule followed by a blank line, then
   an `## Appendix: <Title>` heading. This keeps each file self-contained and
   matches how the existing appendices render.
3. Run `python3 encyclopedia/generate.py` to rebuild `SKILL.md`.

## Do not hand-edit SKILL.md

`skills/forensic-artifacts/SKILL.md` is fully derived: generated entries plus
these appendices. Edits made directly to the appendix region of `SKILL.md` will
be silently overwritten the next time the generator runs — edit the files here
instead.

`python3 encyclopedia/generate.py --check` verifies that the committed
`SKILL.md` matches what the generator would produce, and writes nothing. CI
calls it; run it locally before committing.
