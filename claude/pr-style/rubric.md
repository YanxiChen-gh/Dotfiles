# PR Style Evaluation

The only substantive PR style standard is [pr-authoring.md](../pr-authoring.md), shared by authors,
reviewers, and the cleanup skill. Evaluate its applicable rules; do not maintain a second checklist
here. [Review voice](../review-tone.md) governs outward-facing feedback, not feature-code style.
Historical [examples](../pr-examples.md) are manual calibration references, not prompt inputs.

## Flows

- **Authoring:** evaluate the PR description and testing section against guide sections 3 and 5.
- **Simplify:** evaluate proposed edits against the applicable guide sections and the input.
  Preserve compliant text, necessary rationale, real behavior protection, and verification evidence.
- **Review:** evaluate feedback against the review-voice guide. Use the PR standard to assess
  substantive style findings when the underlying patch or description is available.

## Scoring

For single-artifact scoring, score each applicable rule from 0 to 2: 0 violated, 1 partly followed,
2 followed. Cite the actual span and rule for each finding; explain any criterion excluded for lack
of context. Return the total and up to three concrete, highest-leverage fixes. No violation means
no fix, not an invitation to manufacture work. Scores support critique, not a PR creation gate;
authors still perform the guide's required check before handoff.

## Calibration

`eval/run-eval.sh` keeps candidate generation and judging separate. `AGENT_ENGINE` / `AGENT_MODEL`
select the author or cleaner; `JUDGE_ENGINE` / `JUDGE_MODEL` select the evaluator. Pairwise runs
compare frozen artifacts; cleanup runs withhold the human answer key until judging.
`EVAL_CANDIDATE` reuses a frozen candidate for judge-only reruns.

Corpus and results live in the private `~/style-harness-data` repo, or `$STYLE_HARNESS_DATA`.
Examples and human revisions are calibration evidence, not additional style rules. The evaluator
must distinguish missed corrections from overreach that removes necessary information.
