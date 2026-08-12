---
name: frame-the-problem
description: Select and evidence the problem worth solving before evaluating solutions. Use when an assigned workstream or proposal bundles multiple users, outcomes, or jobs; when the inherited solution may be the wrong starting point; or when the user asks what problem or hypothesis to pursue. Do not use when the problem is already supported and the open question is whether a proposed implementation fills a capability gap; use prove-the-gap then.
argument-hint: "<workstream, assignment, proposal, observations, or links>"
---

# Frame the Problem

Turn an ambiguous mandate into an evidenced problem worth pursuing. Do not optimize the inherited proposal. Reconstruct the current workflow, compare plausible bottlenecks, and use the cheapest observation that can distinguish them.

This skill precedes `prove-the-gap`. It decides which problem deserves attention and whether a causal hypothesis is ready for intervention analysis. `prove-the-gap` evaluates whether a proposed capability should be built.

## Rules

- Treat an assigned deliverable as a stakeholder claim, not proof of the problem.
- Research before asking questions. Do not ask the user for facts available in documents, code, tickets, telemetry, or the current workflow.
- Ask about concrete behavior before abstract goals. A recent case usually reveals more than a polished aspiration.
- Do not brainstorm implementations while candidate problems are still competing.
- Separate verified facts, stakeholder claims, agent assumptions, and missing evidence.
- Preserve legitimate constraints such as a fixed mandate, deadline, or committed customer. They affect the decision but do not prove value.
- Scale the investigation to the cost of being wrong. A reversible one-day decision needs less proof than a platform workstream.
- Do not require certainty. Require enough evidence to justify the next level of commitment.

## Keep The Layers Separate

Write these separately before selecting a direction:

- **Mandate:** the outcome or responsibility the work is meant to advance.
- **Observed problem:** a current condition that harms an actor or blocks the mandate.
- **Mechanism hypothesis:** a falsifiable explanation for why the problem occurs.
- **Intervention:** a change intended to affect that mechanism.
- **Requested solution:** the inherited implementation, which may bundle several interventions.
- **Success and guardrail:** the desired movement and what must not regress.

Use two checks against solution-shaped problem statements:

- **Perfect-solution test:** if the requested solution worked perfectly, which downstream decision, behavior, or result would improve?
- **Subtraction test:** without the requested solution, what important decision or task remains impossible or materially harder?

If neither answer is concrete, do not evaluate the solution yet.

## Workflow

### 1. Check whether problem selection is already complete

Exit quickly with `PURSUE` when primary evidence already establishes the affected actor, observed failure, consequence, and relative importance. Do not invent another discovery exercise. State that the stopping rule is met and hand off to `prove-the-gap` if an intervention is ready to evaluate.

Use the rest of this workflow when the problem, outcome, or priority remains materially uncertain.

### 2. Reconstruct reality

Start from direct links and named workflows. Trace at least one recent case from trigger to outcome:

1. Who encountered the situation?
2. What triggered the workflow?
3. What decisions and handoffs followed?
4. Where did work wait, repeat, fail, or require scarce judgment?
5. What happened afterward: success, abandonment, escalation, ticket, fix, or no action?
6. What information or decisions were discarded?

Use the sources that can change the decision:

1. Current workflow or product behavior.
2. Recent cases, tickets, review notes, support reports, or recordings.
3. Existing metrics, traces, queries, or funnel data.
4. Prior research, proposals, and stakeholder commitments.
5. Code or system inspection when it clarifies what the workflow can currently do.

Do not inventory every adjacent system. Follow the value-losing path to ground.

### 3. Expose contradictions in the mandate

List mismatches before asking the user to resolve them:

- different users named for the same deliverable;
- discovery, judgment, diagnosis, routing, and remediation bundled as one job;
- a success metric that measures output rather than changed behavior;
- a proposed solution whose output does not alter the next decision;
- a local optimization that may not advance the workstream outcome;
- an existing path that appears to perform the proposed job already.

Present the ambiguity map. Do not silently choose the interpretation closest to the requested solution.

### 4. Form candidate problems

Create two to five competing problem statements from different stages of the actual workflow. Use this shape:

```text
<Actor> cannot or does not <important action> during <situation>, causing <observable consequence>. We currently know this from <primary evidence>.
```

For each candidate, state:

- supporting and conflicting evidence;
- frequency, severity, delay, or opportunity cost at the precision available;
- who owns or experiences the consequence;
- the leading mechanism hypotheses;
- the evidence that would demote or eliminate it.

Do not force numerical scoring when the inputs are qualitative. Make the tradeoff legible instead.

### 5. Run a bounded adaptive interview

Ask a question only when all are true:

1. Available evidence cannot answer it.
2. The user is the right source because the answer requires judgment, history, or tribal context.
3. The answer could change the leading problem, verdict, or next test.

Use at most two rounds by default:

- Round one: one to three behavior-based questions after the initial research and ambiguity map.
- Round two: at most two adaptive follow-ups after incorporating the answers and checking available evidence.

Useful prompts include:

- “Walk me through the last case from first signal to final outcome. Where did progress slow or require the most judgment?”
- “Which output changed the next decision, and what happened when it was unavailable?”
- “What happens to cases people reject, abandon, or decide need no action?”
- “Which candidate problem would still matter if the requested solution did not exist?”

Avoid generic survey questions such as “Who are the users?”, “What are the constraints?”, or “What does success look like?” when concrete artifacts can answer them. If the user does not know, convert the unknown into an evidence task instead of continuing to question them.

### 6. Choose the cheapest discriminating test

Name which layer each test addresses:

- **Problem test:** establishes whether the observed pain is real, frequent, or consequential.
- **Mechanism test:** distinguishes why the selected problem occurs.
- **Solution test:** evaluates an intervention. Defer this to `prove-the-gap` unless a tiny intervention is uniquely the cheapest way to test the problem or mechanism.

Prefer evidence in this order:

1. Review existing cases or retained decisions.
2. Observe or time the current workflow.
3. Add temporary, narrow instrumentation.
4. Run a manual or concierge test on a few representative cases.
5. Build a thin prototype only when lower-fidelity evidence cannot answer the question.

State the sample, owner, duration or stopping threshold, expected observation, and what each result would change. The goal is not to eliminate wrong turns. It is to make them cheap.

### 7. Challenge the leading problem

Before the verdict, make the strongest case for the best competing problem:

- Could the observed pain be a symptom rather than the bottleneck?
- Does the selected problem explain the consequence better than its alternatives?
- Would solving it materially change the mandate's outcome?
- Are urgency or organizational enthusiasm substituting for evidence?
- What observation would reverse the selection?

For a material or contested decision, ask one clean-context read-only agent to challenge the evidence packet and proposed verdict. Limit it to three high-confidence findings and resolve them before proceeding.

## Verdicts

Choose exactly one:

- **PURSUE:** Primary evidence supports a material problem relative to the alternatives. State the selected problem, mechanism confidence, and stopping rule. If the mechanism and desired outcome are ready, hand off to `prove-the-gap`. If the mechanism remains uncertain, run only the named mechanism test first.
- **COMPARE:** Two or more problems remain plausible and selecting one now would be arbitrary. Name the cheapest observation that discriminates among them.
- **NEED EVIDENCE:** A load-bearing claim about the problem is unsupported. Request the exact case, observation, measurement, or owner decision needed and pause solution work.
- **DROP:** The candidate problem is immaterial, outside the mandate, unsupported after proportionate investigation, or dominated by a more important problem. State what evidence would reopen it.

Do not use `COMPARE` or `NEED EVIDENCE` to avoid making a judgment after the stopping rule is met.

## Stopping Rule

Stop problem selection when:

- the actor and current workflow are concrete;
- primary evidence supports the observed problem and consequence;
- its importance is proportionate to the proposed investment;
- the strongest competing problem has been considered;
- the desired outcome and guardrail are solution-independent;
- the mechanism is either sufficiently supported or has one bounded test;
- further discovery is unlikely to change what happens next.

For `COMPARE` and `NEED EVIDENCE`, stop when the remaining uncertainty and exact discriminating evidence are explicit. Do not continue interviewing or researching after that point.

## Output

Lead with the verdict. Scale the write-up to the uncertainty and investment. A fast `PURSUE` can be a few bullets.

```markdown
# Verdict: <PURSUE | COMPARE | NEED EVIDENCE | DROP>
<One-sentence decision and confidence.>

## Mandate and current workflow
<The solution-independent outcome and the observed path.>

## Candidate problems
- <Problem>: <supporting and conflicting evidence>

## Selected problem and mechanism
<The problem worth pursuing, the leading causal hypothesis, and what remains uncertain.>

## Evidence
- Fact: <claim> - <citation or concrete observation>
- Claim: <stakeholder assertion>
- Assumption: <unverified belief>

## Cheapest next step
<No further discovery, or one bounded problem/mechanism test with owner and stopping threshold.>

## Handoff
<Proceed to prove-the-gap, compare candidates after named evidence, pause, or drop.>
```

## Interaction Examples

Do research before asking:

```text
Weak: “Who are the users? What is the goal? What are the constraints?”
Better: “The brief names reviewers and engineers, while the research describes a PM reporting workflow. Walk me through the last case: which handoff consumed the most judgment?”
```

Do not lead from hindsight:

```text
Weak: “Are false positives the real problem? Should we track precision?”
Better: “What happens to cases reviewers decide are not real issues, and where is that decision retained?”
```

Exit when the problem is already proven:

```text
Evidence: 200 weekly cases; account lookup consumes 60% of handling time across three systems; the review owner has committed to measure the change.
Verdict: PURSUE. Problem selection is complete. Hand off account-lookup interventions to prove-the-gap.
```

## Common Traps

- Turning the workflow into a fixed questionnaire.
- Asking the user to synthesize evidence the agent can inspect.
- Rephrasing the requested solution as a problem statement.
- Selecting the most technically interesting bottleneck rather than the most consequential one.
- Testing a solution before establishing the problem or mechanism.
- Treating prototype output, usage, or report generation as evidence of changed outcomes.
- Continuing discovery because certainty is impossible.
- Reopening a problem decision that primary evidence and accountable owners have already settled.
