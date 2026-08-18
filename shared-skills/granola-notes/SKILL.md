---
name: granola-notes
description: Access the user's Granola meeting notes through the official API using GRANOLA_API_KEY. Use whenever the user mentions Granola or asks to find, recall, summarize, compare, or quote meeting notes, attendees, action items, summaries, or transcripts stored in Granola.
---

# Granola notes

Use Granola's read-only REST API to answer questions from the user's accessible meeting notes.

## Current API contract

Before making an API request, read Granola's public OpenAPI 3.1 specification:

`https://docs.granola.ai/api-reference/openapi.json`

Treat the specification's `servers`, `paths`, parameters, response schemas, and status codes as authoritative. Inspect only the operations needed for the request. The fallback workflow below is for temporary documentation failures, not a substitute for checking the current specification.

API setup and access-scope documentation:

`https://docs.granola.ai/help-center/sharing/integrations/granola-api`

## Credential boundary

The API key is available only through `GRANOLA_API_KEY`.

- Check only whether the variable is set and non-empty. Never print, inspect, transform, persist, or return its value.
- Never use shell xtrace, `curl --verbose`, `curl --trace`, `env`, `printenv`, or any command that can expose the Authorization header or environment.
- Never ask the user to paste the key into chat. If it is missing, ask them to set `GRANOLA_API_KEY` in their private shell or agent environment and restart the agent if necessary.
- Send the key only as `Authorization: Bearer $GRANOLA_API_KEY` to the server declared by the official OpenAPI specification. Do not send it to documentation hosts or any other service.
- Keep Granola responses in memory. Do not write notes or transcripts to the repository or temporary files unless the user explicitly requests an export.

For shell requests, use quiet failure-aware output and keep the variable expression literal in the command submitted to the shell:

```sh
rtk curl --fail-with-body --silent --show-error \
  -H "Authorization: Bearer ${GRANOLA_API_KEY}" \
  "https://public-api.granola.ai/v1/notes?page_size=10"
```

Do not include the header in logs or repeat the executed command after expansion.

## Retrieval workflow

1. Translate the request into the narrowest available date range, folder, title, owner, or attendee clues. Resolve relative dates to explicit UTC boundaries.
2. Read the relevant OpenAPI path definitions and use their current parameter names and limits.
3. List notes with the narrowest supported server-side filters. Follow opaque cursors until a match is found, the requested time range is exhausted, or `hasMore` is false.
4. Filter note metadata locally by title, owner, and meeting time. Fetch details only for plausible candidates, then use attendees and summary fields to disambiguate.
5. Prefer `summary_markdown` or `summary_text`. Retrieve transcript content only when the user's question requires exact wording or details absent from the summary.
6. If an inline transcript is too large, use the transcript endpoint and follow its opaque cursor until `hasMore` is false or the relevant passage is found.
7. Answer with the matching meeting title, meeting date, and returned `web_url`. Distinguish statements supported by the summary from exact transcript quotations.

If several notes remain plausible, present the smallest useful set of title, date, and owner choices. Ask the user only when those API fields cannot disambiguate the meeting.

## Common fallback operations

Use these only when the OpenAPI specification is temporarily unavailable. The production base URL is `https://public-api.granola.ai`.

| Purpose | Request | Relevant query parameters |
|---|---|---|
| Discover notes | `GET /v1/notes` | `created_before`, `created_after`, `updated_after`, `folder_id`, `cursor`, `page_size` |
| Read a note | `GET /v1/notes/{note_id}` | `include=transcript` only when transcript text is needed |
| Page a transcript | `GET /v1/notes/{note_id}/transcript` | `cursor`, `page_size` |
| Discover folders | `GET /v1/folders` | `cursor`, `page_size` |

Treat note and folder IDs as opaque values returned by the API. Never construct or rewrite a cursor.

## Result and error handling

- **Empty list or unmatched search:** Say "No accessible completed Granola note matched." The API omits notes that do not yet have both a generated summary and transcript, and key access scopes can hide otherwise existing notes. Suggest checking processing state, personal/public scope, date range, or folder before concluding the meeting is absent.
- **400:** Re-read the current path definition. Correct invalid filters, IDs, page sizes, or cursors rather than guessing.
- **401:** Report that Granola rejected the configured key. The key may be missing, invalid, expired, or revoked. Do not inspect it; ask the user to verify or replace it privately.
- **404:** Report that the note is not accessible as a completed note. It may be outside the key's scopes, still processing, never summarized, deleted, or identified by a stale ID.
- **413 / `TRANSCRIPT_TOO_LARGE`:** Retrieve the transcript from the paginated transcript operation instead of requesting it inline.
- **429:** Respect `Retry-After` when present, reduce request concurrency, and stay within Granola's documented rate limit. Do not start an unbounded retry loop.
- **5xx or network failure:** Report the failure and preserve the user's original filters for a bounded retry. Do not claim that no note exists.

## Privacy and scope

Use only notes visible to the configured key. Do not broaden scope, change Granola settings, create webhooks, or share note content outside the user's requested destination. Return only the note content needed to answer the question.
