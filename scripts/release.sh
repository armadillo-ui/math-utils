#!/usr/bin/env bash
set -euo pipefail

# ─── helpers ────────────────────────────────────────────────────────────────

log()  { echo "▸ $*"; }
ok()   { echo "✔ $*"; }
die()  { echo "✖ $*" >&2; exit 1; }

set_output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "$1=$2" >> "$GITHUB_OUTPUT"
  fi
}

skip() {
  echo "─ $*"
  set_output "released" "false"
  exit 0
}

require() {
  for cmd in "$@"; do
    command -v "$cmd" &>/dev/null || die "required: $cmd"
  done
}

# ─── 1. deps check ──────────────────────────────────────────────────────────

require git jq gh npm

# ─── 2. git identity (from env) ─────────────────────────────────────────────

: "${GIT_AUTHOR_NAME:?GIT_AUTHOR_NAME is required}"
: "${GIT_AUTHOR_EMAIL:?GIT_AUTHOR_EMAIL is required}"

export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

# ─── 2b. repo URL ────────────────────────────────────────────────────────────

REPO_URL=$(git remote get-url origin | sed -e 's/\.git$//' -e 's|^git+||')
log "Repo URL: $REPO_URL"

# ─── 3. last tag ────────────────────────────────────────────────────────────

LAST_TAG=$(git describe --tags --match "v[0-9]*" --abbrev=0 2>/dev/null || echo "")
HAS_PREVIOUS_TAG=true

if [[ -z "$LAST_TAG" ]]; then
  log "No previous tag found, starting from v0.0.0"
  LAST_TAG="v0.0.0"
  HAS_PREVIOUS_TAG=false
  COMMITS=$(git log --pretty=format:"%H||%h||%s||%aN" 2>/dev/null)
else
  log "Last tag: $LAST_TAG"
  COMMITS=$(git log "${LAST_TAG}..HEAD" --pretty=format:"%H||%h||%s||%aN")
fi

# ─── 4. detect bump type ────────────────────────────────────────────────────

BUMP=""

while IFS= read -r commit; do
  [[ -z "$commit" ]] && continue
  msg=$(echo "$commit" | cut -d'|' -f5)

  if echo "$msg" | grep -qiE "(BREAKING.CHANGE|^.+!:)"; then
    BUMP="major"
    break
  fi

  if echo "$msg" | grep -qE "^feat(\(.+\))?:"; then
    [[ "$BUMP" != "major" ]] && BUMP="minor"
  fi

  if echo "$msg" | grep -qE "^fix(\(.+\))?:|^perf(\(.+\))?:"; then
    [[ -z "$BUMP" ]] && BUMP="patch"
  fi
done <<< "$COMMITS"

[[ -z "$BUMP" ]] && skip "No releasable commits since $LAST_TAG"

log "Bump type: $BUMP"

# ─── 5. calculate next version ──────────────────────────────────────────────

CURRENT="${LAST_TAG#v}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

VERSION="${MAJOR}.${MINOR}.${PATCH}"
TAG="v${VERSION}"

ok "Next version: $TAG"

# ─── 6. sync package.json ───────────────────────────────────────────────────

log "Updating package.json → $VERSION"
npm version "$VERSION" --no-git-tag-version --allow-same-version
ok "package.json updated"

# ─── 7. generate changelog ──────────────────────────────────────────────────

log "Generating changelog"

if [[ "$HAS_PREVIOUS_TAG" == true ]]; then
  CHANGELOG_ENTRY="## [$TAG]($REPO_URL/compare/$LAST_TAG..$TAG) - $(date +%Y-%m-%d)"
else
  CHANGELOG_ENTRY="## $TAG - $(date +%Y-%m-%d)"
fi
CHANGELOG_ENTRY+=$'\n'

declare -A sections=(
  [feat]="Features"
  [fix]="Bug fixes"
  [perf]="Performance"
  [refactor]="Refactor"
  [docs]="Documentation"
)

for type in feat fix perf refactor docs; do
  type_lines=$(echo "$COMMITS" | grep -E "^[^|]*\|\|[^|]*\|\|${type}(\(.+\))?:" || true)
  if [[ -n "$type_lines" ]]; then
    CHANGELOG_ENTRY+=$'\n'"### ${sections[$type]}"$'\n'
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      full_hash=$(echo "$line" | cut -d'|' -f1)
      short_hash=$(echo "$line" | cut -d'|' -f3)
      raw_msg=$(echo "$line" | cut -d'|' -f5)
      author=$(echo "$line" | cut -d'|' -f7)
      # Strip conventional commit prefix (e.g. "fix: ", "feat(scope): ")
      clean_msg=$(echo "$raw_msg" | sed -E 's/^[a-z]+(\([^)]+\))?!?:[[:space:]]*//')
      CHANGELOG_ENTRY+="- $clean_msg - ([$short_hash]($REPO_URL/commit/$full_hash)) - $author"$'\n'
    done <<< "$type_lines"
  fi
done

GITHUB_CHANGELOG="$CHANGELOG_ENTRY"

if [[ -f CHANGELOG.md ]]; then
  # Insert after the first "- - -" separator (below the header)
  SEPARATOR_LINE=$(grep -n '^- - -$' CHANGELOG.md | head -1 | cut -d: -f1)
  if [[ -n "$SEPARATOR_LINE" ]]; then
    head -n "$SEPARATOR_LINE" CHANGELOG.md > CHANGELOG.md.tmp
    printf '\n%s\n- - -\n' "$CHANGELOG_ENTRY" >> CHANGELOG.md.tmp
    tail -n +$((SEPARATOR_LINE + 1)) CHANGELOG.md >> CHANGELOG.md.tmp
    mv CHANGELOG.md.tmp CHANGELOG.md
  else
    # No separator found — prepend after first line
    EXISTING=$(cat CHANGELOG.md)
    printf '%s\n\n%s\n' "$CHANGELOG_ENTRY" "$EXISTING" > CHANGELOG.md
  fi
else
  echo "$CHANGELOG_ENTRY" > CHANGELOG.md
fi

ok "CHANGELOG.md updated"

# ─── 8. release commit ──────────────────────────────────────────────────────

log "Committing release"
git add package.json package-lock.json CHANGELOG.md
git commit -m "chore(release): $TAG [skip ci]"
ok "Release commit created"

# ─── 9. tag ─────────────────────────────────────────────────────────────────

git tag "$TAG"
ok "Tag created: $TAG"

# ─── 10. push ───────────────────────────────────────────────────────────────

log "Pushing to origin"
git push origin main --follow-tags
ok "Pushed"

# ─── 11. github release ─────────────────────────────────────────────────────

log "Creating GitHub Release"

NOTES_FILE=$(mktemp)
echo "$GITHUB_CHANGELOG" > "$NOTES_FILE"

gh release create "$TAG" \
  --title "$TAG" \
  --notes-file "$NOTES_FILE" \
  --target main

rm -f "$NOTES_FILE"
ok "GitHub Release created: $TAG"

set_output "released" "true"
set_output "version" "$TAG"