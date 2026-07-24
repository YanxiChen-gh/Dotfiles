---
name: prove-the-gap
description: Assess open customer, internal, architectural, and operational build requests before solution design. Use when deciding whether or what to build, reviewing unresolved RFC motivation, or checking whether an existing capability already serves the outcome. Do not use for implementing an approved, scoped decision. Recommends USE EXISTING, PILOT, BUILD, DECLINE, or NEED EVIDENCE from primary evidence.
argument-hint: "<request, RFC, ticket, thread, or links>"
---

# Prove the Gap

Optimize for the customer outcome, not for accepting or rejecting the requested implementation. Be reluctant to add code and infrastructure, but rigorous about evidence. Test both the requester's proposed solution and your first alternative.

Do not restart product discovery when the user asks to implement an already-approved, scoped decision. Use this skill when the decision or scope is still open, or when new evidence puts its premise at risk.

## Rules

- Do not design a production solution until the capability gap is supported by primary evidence.
- A bounded, reversible pilot may be the cheapest way to gather that evidence. Keep its success metric, exit condition, consumer, and time bound explicit.
- Do not make the requester answer questions that available tools can answer.
- Do not use every source ceremonially. Use each source only when it can change the verdict.
- Distinguish capability from discoverability, data existence from fitness for use, and a cheap proof of concept from cheap ownership.
- Treat a ticket or verbal commitment as evidence of ownership, not evidence of value.
- Cite URLs, repository paths, traces, queries, or concrete observations for every load-bearing fact.
- Scale depth to uncertainty, risk, and ownership cost. Use a quick pass for a bounded, reversible decision with clear primary evidence, even when the verdict is a narrow `PILOT` or `BUILD`. Use the full workflow for platform, cross-system, high-risk, contested, or materially uncertain decisions.

## Workflow

### 1. Frame the decision

Write these separately before researching. A quick pass can keep each to one line:

- **Customer outcome:** the decision, task, or harm that needs improvement.
- **Requested implementation:** what someone asked the team to build.
- **Implied gap:** the capability the request assumes is missing.
- **Success signal:** what observable result would prove the outcome improved.
- **Urgency and commitment:** who is blocked now, and who will use and evaluate a solution.

Mark each input as a verified fact, stakeholder claim, or agent assumption. Never let the requested implementation stand in for the outcome.

### 2. Trace the current path end to end

Start with direct links and the named workflow. Find the cheapest observable success signal before studying new infrastructure.

Use the relevant sources in this order:

1. **Existing user path:** exercise the actual UI, API, CLI, plugin, runbook, or manual process when practical. Record what works and the exact residual gap.
2. **Internal context:** at Vanta, use Glean for Slack, Google Workspace, Jira, Guru, ownership, and prior decisions. Invoke `vanta-doc-discovery` when that skill is available; otherwise use Glean directly. Use short targeted searches, then read the primary documents and surrounding threads.
3. **Code and GitHub:** trace the named feature from input through storage, rendering, export, and downstream consumers. Search for existing primitives and inspect relevant issues, PRs, and history. Do not stop at the first suggestive symbol.
4. **Runtime evidence:** use LangSmith traces, Datadog, database queries, or environment inspection only when the decision depends on actual behavior, frequency, coverage, or access. Confirm the workspace and environment first. Prefer read-only inspection and one representative example plus an aggregate over broad exploration.
5. **External source:** read vendor or public documentation only when an external capability or constraint is load-bearing.

For every existing evidence source or alternative path, check the properties that matter for this outcome:

- capability and user friction;
- durability, version history, and race behavior;
- authorization, tenant isolation, and read-only access;
- coverage, frequency, and operational support;
- whether the requester has actually tried it.

### 3. Prefer the lowest-cost evidence path

Evaluate candidates in this order and stop at the first level that can satisfy or test the outcome:

1. Existing user-visible workflow or durable product artifact.
2. Existing API, tool composition, configuration, documentation, or training.
3. Existing persisted domain record, event, trace output, or export.
4. Bounded manual process or temporary instrumentation.
5. Narrow pilot for one committed consumer.
6. New product primitive.
7. Generalized platform or infrastructure.

Do not jump levels because a broader abstraction is cleaner. Reuse is valid only if it meets the required durability, access, and coverage properties.

### 4. Test value and demand

Gather only the precision needed for the decision:

- affected users, teams, or workflows;
- frequency and severity of the blocked outcome;
- observed incidents or failures versus forecast demand;
- time or risk imposed by the current workaround;
- requester commitment to adopt, measure, and report back;
- ongoing security, operations, migration, and maintenance cost of each option.

For platform work, repeated demand or a validated narrow consumer matters more than architectural elegance. For urgent high-severity harm, one strong case can be enough, but state why urgency replaces broader demand evidence.

### 5. Ask only decision-blocking questions

Research first. If evidence is still missing, ask for specific artifacts rather than general context:

- one failing workflow, trace, recording, or reproducible example;
- what existing paths were tried and the exact failure from each;
- one committed consumer and owner;
- a success metric and deadline;
- volume, size, or frequency data that can change the architecture choice.

If the missing answer cannot change the verdict, list it as a residual unknown and stop researching it.

### 6. Compare the real alternatives

Always consider:

- decline or defer;
- use the existing path;
- improve discoverability, documentation, or composition;
- use a bounded manual or operational path;
- run a narrow pilot;
- build the smallest missing primitive;
- build the requested or generalized solution.

Compare ongoing ownership and risk, not just implementation effort. State what evidence would make the broader option win later.

### 7. Run one skeptic pass

For a full-pass decision, ask one clean-context read-only agent to inspect the evidence packet and proposed verdict when delegation is available. Limit it to three high-confidence findings:

```text
Decision at risk: <the proposed conclusion>
Evidence: <a specific contradiction or unsupported premise>
Alternative or question: <one action that could change the verdict>
```

Do not ask it to produce another full analysis. Resolve its findings before the verdict.

For any quick-pass decision, answer the checklist yourself without adding process narration to the output. For a full-pass decision where clean-context delegation is unavailable, disclose the limitation and use the same fallback:

- What evidence would reverse the verdict?
- Did we mistake poor discoverability for a missing capability?
- Did we test the customer outcome rather than the requested interface?
- Did we generalize from one consumer before proving its need?
- Is a manual test or narrow pilot cheaper than production design?
- If data exists, is it durable, authorized, versioned, and available where needed?
- Did we compare maintenance, security, and migration costs rather than prototype effort?

## Verdicts

Choose exactly one:

- **USE EXISTING:** Primary evidence verifies that an existing path can satisfy the outcome. Give exact steps and ask for the residual gap after use. If a path is merely promising but its fitness is unverified, choose `NEED EVIDENCE` and make trying it the evidence request.
- **PILOT:** The gap is credible but value, coverage, or shape is uncertain. Define one consumer, a bounded scope, success and failure metrics, an end date, and what happens afterward.
- **BUILD:** The gap is proven, existing paths are insufficient, impact justifies ownership cost, and the smallest durable production change is understood. Name the broader alternatives that lost and why.
- **DECLINE:** Do not invest in the outcome now because value or commitment is insufficient, or because any proportionate solution costs more than the supported impact. Use `USE EXISTING`, not `DECLINE`, when a verified current path serves a worthwhile outcome. State what new evidence would reopen the decision.
- **NEED EVIDENCE:** A critical unknown can still change the decision. List the exact artifacts or observations needed and pause production design.

Use `NEED EVIDENCE`, not false certainty, when primary evidence is unavailable. Do not use it merely because low-impact details remain unknown.

## Stopping Rule

Stop when all decision-changing claims have support and further research is unlikely to change the verdict. Usually this means:

- the outcome and implied gap are explicit;
- the strongest existing path was exercised or verified from primary evidence;
- at least one real example or exact reproduction supports the gap, unless a verified existing path already makes `USE EXISTING` appropriate;
- demand and impact are measured at the precision the investment requires;
- durability, access, and coverage are verified when the recommendation relies on stored evidence;
- the appropriately scaled skeptic pass is resolved.

For `NEED EVIDENCE`, stop when proportionate research has exhausted the available sources, the remaining critical unknown is explicit, and the output requests the exact artifact or observation that can resolve it. The point is to pause production design, not to search indefinitely for evidence that only the requester or a pilot can create.

Do not inventory adjacent systems, enumerate every stakeholder, or continue searching after the decision is supported. Deep analysis means following the load-bearing path to ground, not searching broadly without a stopping condition.

## Output

Lead with the decision. Keep the write-up decision-oriented and scale its length to the decision. A quick-pass verdict can be a few bullets; a material decision needs the full structure below.

```markdown
# Verdict: <USE EXISTING | PILOT | BUILD | DECLINE | NEED EVIDENCE>
<One-sentence recommendation and confidence.>

## Outcome and gap
<Customer outcome, requested implementation, and the gap actually supported by evidence.>

## Evidence
- Fact: <claim> - <citation>
- Assumption: <claim and why it remains unresolved>

## Cheapest next step
<Existing path, evidence-gathering pilot, smallest build, or no action. Include owner and success/exit criteria when relevant.>

## Why not the broader build
<Ownership cost or unsupported premise that makes broader work premature.>

## Revisit when
<Specific new evidence that would change the verdict.>
```

For `NEED EVIDENCE`, replace the cheapest next step with the exact evidence request. For `USE EXISTING`, `DECLINE`, and `NEED EVIDENCE`, do not append speculative architecture. For `PILOT`, design only the experiment. For `BUILD`, scope the smallest production behavior unless the user separately asks for a design or implementation plan.

## Common Traps

- Adding a new interface when an agent, plugin, API, or runbook already completes the journey.
- Building generalized infrastructure before one committed consumer proves the missing primitive.
- Calling an architecture reversible while ignoring auth, data, networking, deployment, and migration commitments.
- Treating mutable retained state as immutable, evaluator-safe, or audit-safe evidence.
- Using projected adoption to replace current pain, or a customer ticket to replace success criteria.
- Continuing to refine the proposed solution after primary evidence invalidates its premise.
