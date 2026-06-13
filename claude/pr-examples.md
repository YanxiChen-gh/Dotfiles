# PR Examples — calibrating altitude and voice

Real merged PRs from this team, chosen to teach *calibration*: how much to write, at what altitude,
in what voice. These pair with `pr-authoring.md` — the guide gives the principles, these show what
they look like in practice.

**Match the altitude, not the words.** Don't copy "TIN"/"DRY" as a verbal tic; copy the *judgment* —
how much each change earned, given what the diff already shows. The throughline across all of them:
the diff carries the *what*, the description carries only what the diff can't.

---

## 1. Pure move / refactor → one word

[#152353 "Pull out shared auth in mcp and api-external to api-common"](https://github.com/VantaInc/obsidian/pull/152353) (+101/-129)

```markdown
## Changes
TIN

## Motivation
DRY
```

100+ lines changed, but it's a mechanical extraction — the diff *is* the explanation. Nothing to
add, so nothing is added. (Testing was a screenshot proving it still works.)

## 2. Small functional change → one line

[#107707 "Remove unused userId from ToolContext interface"](https://github.com/VantaInc/obsidian/pull/107707) (+11/-78)

```markdown
## Changes
Removes the `userId` field in `ToolContext` and from all the API calls where it was specified

## Motivation
The policies API calls that take `UserId` don't actually need it, and having `UserId` in
`ToolContext` makes it harder for teams building agents that work in Slack / the REST API / etc.
to use the ToolShed.
```

One line for *what* (high altitude — not a file-by-file list), and the real content in *why*. Note
the honest, human deployment note on the actual PR: "Not that safe, need to run the policy agent eval rq."

## 3. Big but mechanical → still TIN; weight goes to Motivation

[#149184 "Upgrade zod from v3 to v4"](https://github.com/VantaInc/obsidian/pull/149184) (+391/-391)

```markdown
## Changes
TIN

## Motivation
Long live zod v4

We're doing zod 4.3.6 and not the latest because in zod v4.4 `z.union([X, z.undefined()])` means
the value can be undefined but the key needs to be there... [+ transitive-dep resolution rationale]

## Deployment
I'd be really sad if reverted
```

Breaks the "bigger change = longer Changes" instinct. The *diff* is mechanical, so Changes is `TIN`;
the *risk* lives in the reasoning, so Motivation does the heavy lifting (version pin, dep
resolution, what reviewers must check). Words go where the risk is, not where the line count is.

## 4. Remove / replace / migrate → decision table

[#151137 "[MCP] Clean up emitted metrics"](https://github.com/VantaInc/obsidian/pull/151137) (+86/-201)

```markdown
## Changes
Remove five of seven custom `vanta.mcp.*` metrics. The two kept carry per-tool names APM can't see.

| Metric | Outcome | Replaced by | Why |
|---|---|---|---|
| `mcp.tool.call` | Kept | — | `tool` tag is invisible to APM; powers the SLO. |
| `mcp.request` | Removed | `trace.express.request.hits` (APM) | APM auto-instruments the handler. |
| `mcp.permission_check` | Removed | structured log line | Highest-volume metric; same data already logged. |
```

When a PR removes/replaces a set of things, one row per item (what happened → replaced by → why) is
the clearest possible before→after. Far more scannable than the same content in prose.

## 5. AI disclosure as a mini-ADR

[#154286 "Add policy version download endpoint to external REST API"](https://github.com/VantaInc/obsidian/pull/154286) (+446/-23)

```markdown
## AI Model used and major prompts used

Claude Opus 4.7 via Claude Code. Brainstormed two endpoint shapes — (a) "always download latest
approved" vs (b) "list versions + download by id" — and landed on a hybrid: a single
`/versions/{versionId}/download` route that mirrors current MCP behavior but stays extensible for a
future versions-list endpoint without breaking changes.
```

When a design decision was actually weighed, the AI-disclosure section is the natural place to record
the alternatives and why you chose one — so reviewers and future readers don't re-litigate it. Skip
the ceremony when nothing was decided; "Claude Code, routine refactor" is enough.

## 6. Extraction / prep refactor → TIN Changes, why-now in Motivation, one rationale comment

[#159332 "Extract maybeApplyInputTransform helper"](https://github.com/VantaInc/obsidian/pull/159332) (+71/-6)

```markdown
## Changes
TIN

## Motivation
Prep for AIPLAT-522 — the regional evaluation runner is about to re-paste this transform-and-count
block, so pull it into a shared helper first. Behavior-preserving.
```

The extraction is right there in the diff, so Changes is `TIN`. What the diff *can't* show is the
why-now — that a second caller is about to need it — so that's the one thing Motivation keeps.

The helper carries a one-line comment for the genuinely non-obvious bit:

```ts
/** Logging is left to the caller so each runner can attach its own context (dataset, region). */
```

That sentence stops the next person from "helpfully" adding a log call here. **One home for each
fact:** because that rationale is evergreen, it lives in the code — so the PR description should
*not* also say "keep the skip logging in the caller." This PR did say it in both; the redundant
bullet is what to drop, not the comment.

---

## Bad → Good (same PR, [#159309](https://github.com/VantaInc/obsidian/pull/159309), +73/-88)

A simple refactor: drop a hand-rolled domain→region cache, let the dataloader do it.

**Too long, AI-sounding** — reconstructs the diff in one dense run-on:

```markdown
## Changes
Before, this file resolved each example's domain to a region by hand: unsafe `as` casts to read the
`domainId`, then a `Set` + per-domain `Map` to dedupe lookups — duplicated across both exported
functions. That hand-rolled cache duplicated what the `DomainToRegion` dataloader already does, and
the casts needed `no-unsafe-type-assertion` escape hatches. Now a zod helper reads the `domainId`
and each function resolves a region per example, leaving deduping to the dataloader.
```

**Right altitude and voice** — one line of *what*, plus the one thing the diff won't show:

```markdown
## Changes
Replace the hand-rolled domain→region cache with the `DomainToRegion` dataloader (and a zod helper
instead of the unsafe `metadata` casts).

Heads up — the diff won't show this: a failed region lookup now logs once per excluded example, not
once per unique domain.
```

What changed: the `Set`+`Map`, the duplication, the eslint-disable are all *in the diff*, so they're
noise here. The behavior change isn't visible in the diff, so it's the one thing worth keeping. And
the voice drops the colon/em-dash pileup and the "behind `no-unsafe-type-assertion` escape hatches"
jargon for something a person would actually say.
