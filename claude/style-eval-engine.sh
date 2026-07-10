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
      claude "${claude_args[@]}" -- "$prompt"
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
    /^BEFORE([ :]|$)/ {
      capture = 1
      print "BEFORE:"
      line = $0
      if (line ~ /^BEFORE:/) {
        sub(/^BEFORE:[[:space:]]*/, "", line)
      } else if (line ~ /^BEFORE \(.*\):/) {
        sub(/^BEFORE \(.*\):[[:space:]]*/, "", line)
      } else {
        line = ""
      }
      if (line != "") print line
      next
    }
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

style_eval_agent_metadata_optional() {
  local key="$1" fallback="$2"
  if [ -z "${EVAL_CANDIDATE:-}" ]; then
    printf '%s\n' "$fallback"
    return
  fi

  local source_metadata value
  source_metadata="$(dirname "$EVAL_CANDIDATE")/metadata.txt"
  value="$(awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$source_metadata")"
  printf '%s\n' "${value:-$fallback}"
}

style_eval_cli_version() {
  case "$1" in
    claude) claude --version ;;
    opencode) opencode --version ;;
  esac
}

style_eval_harness_state_sha256() {
  local harness_root="$1" file
  {
    git -C "$harness_root" diff HEAD --no-ext-diff --binary
    while IFS= read -r -d '' file; do
      printf 'untracked=%s\n' "$file"
      sha256sum "$harness_root/$file"
    done < <(git -C "$harness_root" ls-files --others --exclude-standard -z)
  } | sha256sum | cut -d' ' -f1
}

style_eval_validate_pairwise_json() {
  jq -e '
    (.winner == "A" or .winner == "B") and
    (.confidence | type == "number" and . >= 0 and . <= 1) and
    (.reasons | type == "array") and
    (.anti_tells_in_loser | type == "array")
  ' "$1" >/dev/null
}

style_eval_validate_simplify_json() {
  jq -e '
    ([.examples[].recall | select(. != null)] | if length == 0 then null else add / length end) as $mean |
    (.examples | type == "array" and length > 0) and
    all(.examples[];
      (.example | type == "number") and
      (.caught | type == "array") and
      (.missed | type == "array") and
      (.overreach | type == "array") and
      (.unscored | type == "array") and
      (. as $example |
        (($example.caught | length) + ($example.missed | length)) as $denominator |
        if $denominator == 0 then
          ($example.recall == null)
        else
          ($example.recall | type == "number" and . >= 0 and . <= 1) and
          (($example.recall - (($example.caught | length) / $denominator)) < 0.005) and
          (($example.recall - (($example.caught | length) / $denominator)) > -0.005)
        end) and
      (.cited_right_rule == null or (.cited_right_rule | type == "boolean"))
    ) and
    ($mean != null) and
    ((.mean_recall - $mean) < 0.005 and (.mean_recall - $mean) > -0.005) and
    (.load_bearing_overreach_count | type == "number" and . >= 0 and . == floor)
  ' "$1" >/dev/null
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
  shift 2
  local agent_engine agent_cli_version agent_model agent_profile agent_variant harness_root harness_dirty harness_state_sha256
  agent_engine="$(style_eval_agent_metadata agent_engine "${AGENT_ENGINE:-claude}")"
  if [ -n "${EVAL_CANDIDATE:-}" ]; then
    agent_cli_version="$(style_eval_agent_metadata_optional agent_cli_version unknown)"
  else
    agent_cli_version="$(style_eval_cli_version "$agent_engine")"
  fi
  agent_model="$(style_eval_agent_metadata agent_model "${AGENT_MODEL:-configured-default}")"
  agent_profile="$(style_eval_agent_metadata agent_profile "${AGENT_PROFILE:-build}")"
  agent_variant="$(style_eval_agent_metadata agent_variant "${AGENT_VARIANT:-configured-default}")"
  harness_root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
  if [ -n "$(git -C "$harness_root" status --short)" ]; then
    harness_dirty=true
  else
    harness_dirty=false
  fi
  harness_state_sha256="$(style_eval_harness_state_sha256 "$harness_root")"
  cat >"$dir/metadata.txt" <<EOF
benchmark=$benchmark
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
harness_git_sha=$(git -C "$harness_root" rev-parse HEAD)
harness_git_dirty=$harness_dirty
harness_git_state_sha256=$harness_state_sha256
agent_engine=$agent_engine
agent_cli_version=$agent_cli_version
agent_model=$agent_model
agent_profile=$agent_profile
agent_variant=$agent_variant
judge_engine=${JUDGE_ENGINE:-claude}
judge_cli_version=$(style_eval_cli_version "${JUDGE_ENGINE:-claude}")
judge_model=${JUDGE_MODEL:-opus}
judge_profile=${JUDGE_PROFILE:-build}
judge_variant=${JUDGE_VARIANT:-configured-default}
EOF

  local source_index=0 source
  for source in "$@"; do
    source_index=$((source_index + 1))
    printf 'source_%d_path=%s\n' "$source_index" "$source" >>"$dir/metadata.txt"
    printf 'source_%d_sha256=%s\n' "$source_index" "$(sha256sum "$source" | cut -d' ' -f1)" >>"$dir/metadata.txt"
  done
}
