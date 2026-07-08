#!/usr/bin/env bash

style_eval_engine() {
  local role="$1" prompt="$2" trace_file="${3:-}"
  local engine model profile variant

  if [ "$role" = "agent" ]; then
    engine="${AGENT_ENGINE:-claude}"
    model="${AGENT_MODEL:-}"
    profile="${AGENT_PROFILE:-build}"
    variant="${AGENT_VARIANT:-}"
  else
    engine="${JUDGE_ENGINE:-claude}"
    model="${JUDGE_MODEL:-opus}"
    profile="${JUDGE_PROFILE:-build}"
    variant="${JUDGE_VARIANT:-}"
  fi

  case "$engine" in
    claude)
      local claude_args=(-p --output-format text --no-session-persistence --tools "")
      [ -n "$model" ] && claude_args+=(--model "$model")
      claude "${claude_args[@]}" "$prompt"
      ;;
    opencode)
      local opencode_args=(run --agent "$profile")
      [ -n "$model" ] && opencode_args+=(--model "$model")
      [ -n "$variant" ] && opencode_args+=(--variant "$variant")

      if [ -z "$trace_file" ]; then
        opencode "${opencode_args[@]}" -- "$prompt"
        return
      fi

      command -v jq >/dev/null 2>&1 || {
        echo "jq is required to capture a blind OpenCode eval trace" >&2
        return 1
      }
      opencode "${opencode_args[@]}" --format json -- "$prompt" |
        tee "$trace_file" |
        jq -r 'select(.type == "text") | .part.text'
      if jq -e 'select(.type == "tool_use" or .type == "tool" or .part.type == "tool")' "$trace_file" >/dev/null; then
        echo "agent used a tool during a blind eval; rejecting the candidate" >&2
        return 1
      fi
      ;;
    *)
      echo "unsupported $role engine: $engine (expected claude or opencode)" >&2
      return 1
      ;;
  esac
}

style_eval_slug() {
  printf '%s' "$1" | tr -cs '[:alnum:]._-' '-'
}

style_eval_blind_before() {
  awk '
    /^## [0-9]+\./ {
      number = $2
      sub(/\.$/, "", number)
      print "## Example " number
      capture = 0
      next
    }
    /^BEFORE([ :]|$)/ { capture = 1; print "BEFORE:"; next }
    /^AFTER([ :]|$)/ { capture = 0; next }
    capture { print }
  ' "$1"
}

style_eval_require_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "jq is required to validate eval output" >&2
    return 1
  }
}

style_eval_agent_metadata() {
  local key="$1" fallback="$2"
  if [ -z "${EVAL_CANDIDATE:-}" ]; then
    printf '%s\n' "$fallback"
    return
  fi

  local source_metadata value
  source_metadata="$(dirname "$EVAL_CANDIDATE")/metadata.txt"
  [ -f "$source_metadata" ] || {
    echo "frozen candidate metadata not found: $source_metadata" >&2
    return 1
  }
  value="$(awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$source_metadata")"
  [ -n "$value" ] || {
    echo "frozen candidate metadata is missing $key: $source_metadata" >&2
    return 1
  }
  printf '%s\n' "$value"
}

style_eval_normalize_json() {
  awk '
    NR == 1 && /^```(json)?$/ { fenced = 1; next }
    fenced && /^```$/ { next }
    { print }
  '
}

style_eval_run_dir() {
  local results="$1" benchmark="$2"
  local run_id benchmark_slug agent_engine agent_model judge_engine judge_model dir
  run_id="$(style_eval_slug "${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}")"
  benchmark_slug="$(style_eval_slug "$benchmark")"
  agent_engine="$(style_eval_agent_metadata agent_engine "${AGENT_ENGINE:-claude}")" || return 1
  agent_engine="$(style_eval_slug "$agent_engine")"
  agent_model="$(style_eval_agent_metadata agent_model "${AGENT_MODEL:-configured-default}")" || return 1
  agent_model="$(style_eval_slug "$agent_model")"
  judge_engine="$(style_eval_slug "${JUDGE_ENGINE:-claude}")"
  judge_model="$(style_eval_slug "${JUDGE_MODEL:-opus}")"
  dir="$results/runs/$run_id-$benchmark_slug-$agent_engine-$agent_model-judged-by-$judge_engine-$judge_model"
  if [ -e "$dir" ]; then
    echo "result directory already exists: $dir (set a different RUN_ID)" >&2
    return 1
  fi
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

style_eval_write_metadata() {
  local dir="$1" benchmark="$2"
  local agent_engine agent_model agent_profile agent_variant
  agent_engine="$(style_eval_agent_metadata agent_engine "${AGENT_ENGINE:-claude}")"
  agent_model="$(style_eval_agent_metadata agent_model "${AGENT_MODEL:-configured-default}")"
  agent_profile="$(style_eval_agent_metadata agent_profile "${AGENT_PROFILE:-build}")"
  agent_variant="$(style_eval_agent_metadata agent_variant "${AGENT_VARIANT:-configured-default}")"
  cat >"$dir/metadata.txt" <<EOF
benchmark=$benchmark
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
agent_engine=$agent_engine
agent_model=$agent_model
agent_profile=$agent_profile
agent_variant=$agent_variant
judge_engine=${JUDGE_ENGINE:-claude}
judge_model=${JUDGE_MODEL:-opus}
judge_profile=${JUDGE_PROFILE:-build}
judge_variant=${JUDGE_VARIANT:-configured-default}
EOF
}
