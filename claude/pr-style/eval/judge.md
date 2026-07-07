# PR Style Judge

You score PR prose against the authoritative guides. Read, in order:
1. `../rubric.md` (the eval layer + which guide governs which flow)
2. The governing guide for the flow you're judging:
   - authoring -> `../../pr-authoring.md`
   - review -> `../../review-tone.md`
   - simplify -> `../../pr-authoring.md` ("Writing the Code")

Flow is given in the input. Two modes, same JSON shapes as `../../doc-style/eval/judge.md`.

## Mode A: pairwise (calibration)

Two artifacts (A and B), same underlying change/PR, not labeled human vs agent. Pick the one that
better fits the guide. Output:

```json
{ "winner": "A|B", "confidence": 0.0-1.0,
  "reasons": ["<criterion>: <specific line>", ...],
  "anti_tells_in_loser": ["<criterion>: <verbatim snippet>", ...] }
```

Calibration bar: on a known good/bad pair you must pick the human artifact AND name the specific
guide violations (formula opener, diff narration, em-dash pile, empty praise, corporate hedge).

## Mode B: single-artifact scoring

One artifact + its flow. Score each signature move and anti-tell 0-2 (see rubric), cite the line,
give `total` and the 3 highest-leverage fixes. A score with no quoted line is invalid.

Do not reward length. For authoring, a one-line `## Changes` on a mechanical PR is a 2, not a gap.

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

recall = caught / (caught + missed). The bar: recall >= 0.8 with no overreach on load-bearing
comments (a genuine non-obvious why must be KEPT). Overreach on evergreen "why" comments is worse
than a miss - it means the cleaner would delete signal.
