# PR Style Judge

Evaluate the supplied canonical PR standard (`../../../agent-rules/guides/pr-authoring.md`) using the flow and
scoring instructions in `../rubric.md`. Review feedback also uses `../../../agent-rules/guides/review-tone.md`.
These guides are supplied in blind eval prompts; do not assume file access or invent rules
from examples. Flow is given in the input.

## Mode A: pairwise (calibration)

Two artifacts (A and B), same underlying change/PR, not labeled human vs agent. Pick the one that
better fits the guide. Output:

```json
{ "winner": "A|B", "confidence": 0.0-1.0,
  "reasons": ["<criterion>: <specific line>", ...],
  "anti_tells_in_loser": ["<criterion>: <verbatim snippet>", ...] }
```

Prefer the artifact that follows the applicable guide rules. Name concrete violations with
quoted evidence; do not infer quality from length or presumed human/agent authorship.

## Mode B: single-artifact scoring

One artifact + its flow. Score each applicable guide rule 0-2 (see rubric), cite the affected
span for violations, and give `total` and up to three highest-leverage fixes. Exclude rules
that cannot be assessed from the supplied context and explain why. Do not reward length or
invent fixes for compliant work.

## Mode C: simplify recall calibration

For the priority flow. Input: an example's BEFORE (messy comment/test/PR-description) with the
AFTER withheld, plus the cleaner's output (what it proposed to CUT/TIGHTEN). You are given the
real AFTER separately as the answer key. Score how well the cleaner reproduced the human edit.

```json
{ "caught": ["<edit the human made that the cleaner also flagged>"],
  "missed": ["<edit the human made that the cleaner did NOT flag>"],
  "overreach": ["<cut the cleaner proposed that the human KEPT>"],
  "recall": 0.0-1.0, "cited_right_rule": true|false }
```

recall = caught / (caught + missed). The bar: recall >= 0.8 with no overreach on explanations
required by section 4 of the canonical guide. Such overreach is worse than a miss.
