#!/usr/bin/env bash
# changelog.sh — Generate a changelog entry from tab-delimited commit lines.
#
# Usage (sourced):
#   source scripts/changelog.sh
#   entry=$(generate_changelog_entry "$TAG" "$LAST_TAG" "$REPO_URL" "$HAS_PREVIOUS_TAG" "$COMMITS")
#
# COMMITS format (tab-separated, one per line):
#   <full_hash>\t<short_hash>\t<message>\t<author>

generate_changelog_entry() {
  local tag="$1"
  local last_tag="$2"
  local repo_url="$3"
  local has_previous_tag="$4"
  local commits="$5"

  local entry=""

  # Header with compare link (or plain if no previous tag)
  if [[ "$has_previous_tag" == true ]]; then
    entry="## [$tag]($repo_url/compare/$last_tag..$tag) - $(date +%Y-%m-%d)"
  else
    entry="## $tag - $(date +%Y-%m-%d)"
  fi
  entry+=$'\n'

  local type type_lines title

  for type in feat fix perf refactor docs; do
    case "$type" in
      feat)     title="Features" ;;
      fix)      title="Bug fixes" ;;
      perf)     title="Performance" ;;
      refactor) title="Refactor" ;;
      docs)     title="Documentation" ;;
    esac

    type_lines=$(printf "%s\n" "$commits" | awk -F '\t' -v t="$type" '
      $3 ~ ("^" t "(\\(.+\\))?!?:") { print }
    ')

    if [[ -n "$type_lines" ]]; then
      entry+=$'\n'"### $title"$'\n'

      while IFS=$'\t' read -r full_hash short_hash raw_msg author; do
        [[ -z "$raw_msg" ]] && continue

        clean_msg=$(echo "$raw_msg" | sed -E 's/^(feat|fix|perf|refactor|docs)(\([^)]+\))?!?:[[:space:]]*//')

        entry+="- $clean_msg - ([$short_hash]($repo_url/commit/$full_hash)) - $author"$'\n'
      done <<< "$type_lines"
    fi
  done

  printf '%s' "$entry"
}

insert_changelog_entry() {
  local entry="$1"
  local file="${2:-CHANGELOG.md}"

  if [[ -f "$file" ]]; then
    # Insert after the first "- - -" separator (below the header)
    local separator_line
    separator_line=$(grep -n '^- - -$' "$file" | head -1 | cut -d: -f1)
    if [[ -n "$separator_line" ]]; then
      head -n "$separator_line" "$file" > "${file}.tmp"
      printf '%s\n- - -\n' "$entry" >> "${file}.tmp"
      tail -n +$((separator_line + 1)) "$file" >> "${file}.tmp"
      mv "${file}.tmp" "$file"
    else
      # No separator found — prepend
      local existing
      existing=$(cat "$file")
      printf '%s\n\n%s\n' "$entry" "$existing" > "$file"
    fi
  else
    echo "$entry" > "$file"
  fi
}
