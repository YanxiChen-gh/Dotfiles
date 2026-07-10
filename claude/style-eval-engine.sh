#!/usr/bin/env bash

style_eval_engine() {
  style_eval_engine_run "$1" "$2" "" "${3:-}"
}

style_eval_engine_file() {
  local role="$1" prompt_file="$2" trace_file="${3:-}"
  [ -f "$prompt_file" ] || {
    echo "eval prompt file not found: $prompt_file" >&2
    return 1
  }
  style_eval_engine_run "$role" "" "$prompt_file" "$trace_file"
}

style_eval_engine_run() {
  local role="$1" prompt="$2" prompt_file="$3" trace_file="$4"
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
      local claude_args=(-p --no-session-persistence --tools "")
      [ -n "$model" ] && claude_args+=(--model "$model")
      if [ -n "$trace_file" ]; then
        if [ -n "$prompt_file" ]; then
          claude "${claude_args[@]}" --output-format json <"$prompt_file" |
            tee "$trace_file" |
            jq -r '.result'
        else
          claude "${claude_args[@]}" --output-format json -- "$prompt" |
            tee "$trace_file" |
            jq -r '.result'
        fi
      elif [ -n "$prompt_file" ]; then
        claude "${claude_args[@]}" --output-format text <"$prompt_file"
      else
        claude "${claude_args[@]}" --output-format text -- "$prompt"
      fi
      ;;
    opencode)
      local opencode_args=(run --agent "$profile")
      [ -n "$model" ] && opencode_args+=(--model "$model")
      [ -n "$variant" ] && opencode_args+=(--variant "$variant")

      if [ -z "$trace_file" ]; then
        if [ -n "$prompt_file" ]; then
          opencode "${opencode_args[@]}" <"$prompt_file"
        else
          opencode "${opencode_args[@]}" -- "$prompt"
        fi
        return
      fi

      command -v jq >/dev/null 2>&1 || {
        echo "jq is required to capture a blind OpenCode eval trace" >&2
        return 1
      }
      if [ -n "$prompt_file" ]; then
        opencode "${opencode_args[@]}" --format json <"$prompt_file" |
          tee "$trace_file" |
          jq -r 'select(.type == "text") | .part.text'
      else
        opencode "${opencode_args[@]}" --format json -- "$prompt" |
          tee "$trace_file" |
          jq -r 'select(.type == "text") | .part.text'
      fi
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
    def nonempty_strings:
      type == "array" and length > 0 and
      all(.[]; type == "string" and length > 0);
    (.winner == "A" or .winner == "B") and
    (.confidence | type == "number" and . >= 0 and . <= 1) and
    (.reasons | nonempty_strings) and
    (.anti_tells_in_loser | nonempty_strings)
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

style_eval_validate_manifest_simplify_json() {
  local judgment="$1" manifest="$2"
  jq -e --slurpfile manifest "$manifest" '
    def same_strings($left; $right):
      ($left | length) == ($left | unique | length) and
      ($right | length) == ($right | unique | length) and
      ($left | sort) == ($right | sort);
    def strings: type == "array" and all(.[]; type == "string");
    ($manifest[0].cases | map(select(.flow == "simplify"))) as $cases |
    ($cases | map({key: .id, value: .}) | from_entries) as $case_by_id |
    ($cases | map(.id)) as $expected_ids |
    (.examples | type == "array" and length > 0) and
    ([.examples[].case_id] | same_strings(.; $expected_ids)) and
    all(.examples[];
      . as $example |
      ($case_by_id[$example.case_id]) as $case |
      ($case != null) and
      ($example.caught | strings) and
      ($example.missed | strings) and
      ($example.overreach | strings) and
      ($example.load_bearing_overreach | strings) and
      ($example.unscored | strings) and
      ([($example.caught + $example.missed)[]] | same_strings(.; $case.scoring.expected_edits)) and
      ($example.overreach | length == ($example.overreach | unique | length)) and
      ($example.load_bearing_overreach | length == ($example.load_bearing_overreach | unique | length)) and
      all($example.load_bearing_overreach[]; . as $item |
        ($example.overreach | index($item)) != null and
        ($case.scoring.must_preserve | index($item)) != null) and
      (($example.caught | length) + ($example.missed | length)) as $denominator |
      ($denominator > 0) and
      ($example.recall | type == "number" and . >= 0 and . <= 1) and
      (($example.recall - (($example.caught | length) / $denominator)) | fabs < 0.000001) and
      ($example.cited_right_rule | type == "boolean")
    ) and
    ([.examples[].recall] | add / length) as $mean |
    (.mean_recall | type == "number") and
    ((.mean_recall - $mean) | fabs < 0.000001) and
    ([.examples[].load_bearing_overreach[]] | length) as $load_bearing_count |
    (.load_bearing_overreach_count | type == "number" and . == floor) and
    (.load_bearing_overreach_count == $load_bearing_count)
  ' "$judgment" >/dev/null
}

style_eval_validate_manifest_authoring_summary() {
  local summary="$1" manifest="$2"
  jq -e --slurpfile manifest "$manifest" '
    def same_strings($left; $right):
      ($left | length) == ($left | unique | length) and
      ($right | length) == ($right | unique | length) and
      ($left | sort) == ($right | sort);
    def nonempty_strings:
      type == "array" and length > 0 and
      all(.[]; type == "string" and length > 0);
    ($manifest[0].cases | map(select(.flow == "authoring"))) as $manifest_cases |
    ($manifest_cases | map(.id)) as $expected_ids |
    ($manifest_cases | map({key: .id, value: .}) | from_entries) as $case_by_id |
    (.flow == "authoring") and
    (.cases | type == "array") and
    ([.cases[].case_id] | same_strings(.; $expected_ids)) and
    all(.cases[];
      (.case_id | type == "string") and
      (.winner == "A" or .winner == "B") and
      (.reference_slot == "A" or .reference_slot == "B") and
      (.reference_won | type == "boolean") and
      (.reference_won == (.winner == .reference_slot)) and
      (.expected_reasons | nonempty_strings) and
      (.expected_reasons == $case_by_id[.case_id].scoring.reasons)
    ) and
    (.total | type == "number" and . == floor and . == ($expected_ids | length)) and
    (.total == (.cases | length)) and
    (.reference_wins | type == "number" and . == floor and . >= 0) and
    (.reference_wins == ([.cases[] | select(.reference_won)] | length))
  ' "$summary" >/dev/null
}

style_eval_normalize_json() {
  awk '
    NR == 1 && /^```(json)?$/ { fenced = 1; next }
    fenced && /^```$/ { next }
    { print }
  '
}

style_eval_run_dir() {
  local results="$1" benchmark="$2" decision_mode="${3:-judged}"
  local run_id benchmark_slug agent_engine agent_model judge_engine judge_model dir
  run_id="$(style_eval_slug "${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}")"
  benchmark_slug="$(style_eval_slug "$benchmark")"
  agent_engine="$(style_eval_agent_metadata agent_engine "${AGENT_ENGINE:-claude}")" || return 1
  agent_engine="$(style_eval_slug "$agent_engine")"
  agent_model="$(style_eval_agent_metadata agent_model "${AGENT_MODEL:-configured-default}")" || return 1
  agent_model="$(style_eval_slug "$agent_model")"
  if [ "$decision_mode" = agent ]; then
    dir="$results/runs/$run_id-$benchmark_slug-agent-decision-$agent_engine-$agent_model"
  else
    judge_engine="$(style_eval_slug "${JUDGE_ENGINE:-claude}")"
    judge_model="$(style_eval_slug "${JUDGE_MODEL:-opus}")"
    dir="$results/runs/$run_id-$benchmark_slug-$agent_engine-$agent_model-judged-by-$judge_engine-$judge_model"
  fi
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
