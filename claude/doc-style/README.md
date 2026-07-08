# doc-style

A harness that makes agents write docs the way I do, plus a local eval to prove it works.

The finding it's built on: agent docs and mine on the *same topic* differ in **structure and
stance**, not vocabulary. The agent's Day-1 playbook was 3,646 words; mine was 909 for the same
payload. So the harness polices bloat, hedging, false precision, and a missing thesis - not word
choice.

## Layout

- `rubric.md` - single source of truth. Signature moves, anti-tells, contrastive pairs. Edit this
  to change the style; authoring, review, and eval all read from it.
- the `doc-authoring` skill lives at `../skills/doc-authoring/SKILL.md` (registered via symlink in
  `~/.claude/skills/`, so agents auto-discover it). Loads this rubric, links exemplars, enforces a
  draft-then-cut pass. Fires when I ask an agent to write a doc.
- `reviewer.md` - read-only pre-`gsync` gate. Scores a draft and returns a ranked fix list in my
  review-tone. Run it before syncing a `.md` to a Google Doc.
- `eval/` - local eval (code only; data is in the private repo, see below).
  - `judge.md` - the judge prompt (pairwise + single-doc modes).
  - `run-eval.sh calibrate` - blind pairwise: does the judge prefer the human doc?
  - `run-eval.sh score FILE` - rubric-score one doc.
  - `run-eval.sh rewrite` - have the agent rewrite the golden agent doc, freeze its output, then
    have the judge compare it with the human doc.

The agent under test and evaluator are separate. Select them with `AGENT_ENGINE` / `AGENT_MODEL`
and `JUDGE_ENGINE` / `JUDGE_MODEL`; the judge defaults to Claude Opus. For example:

```bash
AGENT_ENGINE=opencode AGENT_MODEL=openai/gpt-5.6-sol AGENT_VARIANT=high \
  JUDGE_ENGINE=claude JUDGE_MODEL=opus ./eval/run-eval.sh rewrite
```

Blind OpenCode runs retain a JSONL trace and fail if the agent uses tools, preventing it from
reading the withheld human counterpart. Set `EVAL_CANDIDATE` to a frozen candidate file to rerun
only the judge without spending another agent sample.

## Data (private)

Corpus and results reference internal content, so they live in a PRIVATE repo, not here. The evals
read `$STYLE_HARNESS_DATA` (default `~/style-harness-data`):

```bash
git clone git@github.com:YanxiChen-gh/style-harness-data.git ~/style-harness-data
```

Then `run-eval.sh` works. Corpus layout there: `doc-style/corpus/human/` (my real docs, positive),
`doc-style/corpus/agent/` (counterparts, negative), `ground-truth-comments.md` (my real review
comments = the calibration answer key). Results land in `doc-style/results/`.

## The two-layer eval

1. **Calibrate the judge.** On the golden pair, the judge must pick my doc AND independently name
   the bloat, the "15,000+" false precision, and the buried opener. If it can't, the rubric/judge
   is wrong - fix that before trusting any other number.
2. **Measure the system.** Once calibrated, generate harness-on vs harness-off docs on held-out
   prompts and score them. Win-rate + anti-tell counts over time.

## Extending the corpus

Only one real agent-vs-human pair exists today (Day-1 playbook). To strengthen calibration,
generate agent counterparts for the other 5 human docs: prompt a vanilla agent with a one-line ask
reversed out of each doc, save to `corpus/agent/NN-*.md`. Then `run-eval.sh calibrate` covers 6
pairs instead of 1.
