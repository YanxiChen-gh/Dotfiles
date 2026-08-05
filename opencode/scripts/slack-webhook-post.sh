#!/usr/bin/env bash

set -euo pipefail

channel_slug=${1:-}
message_file=${2:-}

if [[ ! $channel_slug =~ ^[a-z0-9][a-z0-9-]*$ ]] || [[ -z $message_file ]]; then
    printf 'Usage: %s <channel-slug> <message-file|->\n' "$0" >&2
    exit 1
fi

if [[ $channel_slug == default ]]; then
    webhook_file=$HOME/.claude/secrets/slack-webhook.txt
else
    webhook_file=$HOME/.claude/secrets/slack-webhook-$channel_slug.txt
fi

if [[ -L $webhook_file || ! -f $webhook_file || ! -r $webhook_file || ! -O $webhook_file ]]; then
    printf 'Slack webhook is not a readable, user-owned regular file.\n' >&2
    exit 2
fi

webhook_mode=$(stat -c '%a' "$webhook_file" 2>/dev/null || stat -f '%Lp' "$webhook_file")
if [[ $webhook_mode != 600 ]]; then
    printf 'Slack webhook must have mode 600.\n' >&2
    exit 2
fi

if [[ $message_file != - && (! -f $message_file || ! -r $message_file) ]]; then
    printf 'Slack message file is not readable.\n' >&2
    exit 3
fi

webhook_url=$(tr -d '[:space:]' < "$webhook_file")
if [[ $webhook_url != https://hooks.slack.com/services/* ]]; then
    printf 'Slack webhook file does not contain a valid incoming webhook URL.\n' >&2
    exit 4
fi

payload_file=$(mktemp "${TMPDIR:-/tmp}/slack-webhook-payload.XXXXXX")
trap 'rm -f "$payload_file"' EXIT
chmod 600 "$payload_file"

if [[ $message_file == - ]]; then
    python3 -c 'import json, sys; json.dump({"text": sys.stdin.read()}, sys.stdout)' > "$payload_file"
else
    python3 -c 'import json, pathlib, sys; json.dump({"text": pathlib.Path(sys.argv[1]).read_text()}, sys.stdout)' "$message_file" > "$payload_file"
fi

printf 'url = "%s"\n' "$webhook_url" | curl \
    --config - \
    --request POST \
    --header 'Content-Type: application/json' \
    --data-binary "@$payload_file" \
    --connect-timeout 2 \
    --max-time 5 \
    --silent \
    --show-error \
    --fail \
    --output /dev/null
