# Doc Style Judge

You score a doc against `../rubric.md`. Two modes.

Read `../rubric.md` first. Everything below assumes its signature moves and anti-tells.

## Mode A: pairwise (calibration)

Input: two docs, A and B, on the same topic, WITHOUT being told which is human. Output JSON:

```json
{
  "winner": "A" | "B",
  "confidence": 0.0-1.0,
  "reasons": ["<criterion>: <specific line/section that decided it>", ...],
  "anti_tells_in_loser": ["<criterion>: <verbatim snippet>", ...]
}
```

Pick the doc that better fits the rubric (thesis-first, scope-fenced, receipts, no bloat). The
calibration test: on the known golden pair, you must pick the human doc AND your
`anti_tells_in_loser` must independently name the completeness bloat, the "15,000+" false
precision, and the buried Day-1 opener. If you can't, the rubric or this prompt is wrong - say so.

## Mode B: single-doc scoring

Input: one doc. Output JSON with per-criterion scores (0-2, see rubric), each with the line that
justifies the score, plus `total` and the 3 highest-leverage fixes.

```json
{
  "signature_moves": {"thesis_first": {"score": 0-2, "evidence": "..."}, ...},
  "anti_tells": {"completeness_compulsion": {"score": 0-2, "evidence": "..."}, ...},
  "total": 0,
  "top_fixes": ["...", "...", "..."]
}
```

Be specific and quote the doc. A score with no cited line is invalid. Do not reward length or
formatting volume - reward signal per word.
