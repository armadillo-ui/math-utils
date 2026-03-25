#!/usr/bin/env bash
set -euo pipefail

# ─── helpers ────────────────────────────────────────────────────────────────

log()  { echo "ℹ $*"; }
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

require git gh npm jq

# ─── 2. git identity (from env) ─────────────────────────────────────────────

: "${GIT_AUTHOR_NAME:?GIT_AUTHOR_NAME is required}"
: "${GIT_AUTHOR_EMAIL:?GIT_AUTHOR_EMAIL is required}"

export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

#   HTTPS: https://github.com/org/repo.git  → https://github.com/org/repo
#   SSH:   git@github.com:org/repo.git      → https://github.com/org/repo
#   git+:  git+https://github.com/org/repo  → https://github.com/org/repo
raw_url=$(git remote get-url origin)
REPO_URL=$(echo "$raw_url" \
  | sed -e 's/\.git$//' \
        -e 's|^git+||' \
        -e 's|^git@\([^:]*\):\(.*\)|https://\1/\2|')
log "Repo URL: $REPO_URL"

# ─── 3. last tag ────────────────────────────────────────────────────────────

LAST_TAG=$(git describe --tags --match "v[0-9]*" --abbrev=0 2>/dev/null || echo "")
HAS_PREVIOUS_TAG=true

if [[ -z "$LAST_TAG" ]]; then
  log "No previous tag found, starting from v0.0.0"
  LAST_TAG="v0.0.0"
  HAS_PREVIOUS_TAG=false
  COMMITS=$(git log --pretty=format:"%H%x09%h%x09%s%x09%aN" 2>/dev/null)
else
  log "Last tag: $LAST_TAG"
  COMMITS=$(git log "${LAST_TAG}..HEAD" --pretty=format:"%H%x09%h%x09%s%x09%aN")
fi

# ─── 4. detect bump type ────────────────────────────────────────────────────

BUMP=""

# Regex correcta según Conventional Commits spec:
#   ^[a-z]+(\([^)]+\))?!:  →  tipo en minúsculas + scope opcional + ! + :
while IFS=$'\t' read -r _hash _short msg _author; do
  [[ -z "$msg" ]] && continue

  if echo "$msg" | grep -qE "^[a-z]+(\([^)]+\))?!:"; then
    BUMP="major"
    break
  fi

  if echo "$msg" | grep -qE "^feat(\([^)]+\))?:"; then
    [[ "$BUMP" != "major" ]] && BUMP="minor"
  fi

  if echo "$msg" | grep -qE "^(fix|perf)(\([^)]+\))?:"; then
    [[ -z "$BUMP" ]] && BUMP="patch"
  fi
done <<< "$COMMITS"

# (segundo mecanismo según spec: "BREAKING CHANGE:" en el body)
# Se hace fuera del loop para no releer todos los commits dentro de él
if [[ "$BUMP" != "major" ]]; then
  if git log "${LAST_TAG}..HEAD" --pretty=format:"%B" 2>/dev/null \
     | grep -qiE "^BREAKING[- ]CHANGE:"; then
    BUMP="major"
  fi
fi

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

# ─── 7. npm publish ─────────────────────────────────────────────────────────
# Publish BEFORE any git operation so that if it fails, the remote is untouched
# and there is nothing to rollback. The workflow already ran `npm run build`
# before this script, so dist/ is ready.

log "Publishing to npm registry"
if ! npm publish; then
  die "npm publish failed — no git changes were pushed, remote is clean"
fi
ok "Published to npm registry"

# ─── 8. generate changelog ──────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/changelog.sh"

log "Generating changelog"

CHANGELOG_ENTRY=$(generate_changelog_entry "$TAG" "$LAST_TAG" "$REPO_URL" "$HAS_PREVIOUS_TAG" "$COMMITS")
GITHUB_CHANGELOG="$CHANGELOG_ENTRY"

insert_changelog_entry "$CHANGELOG_ENTRY" CHANGELOG.md

ok "CHANGELOG.md updated"

# ─── 9. release commit ──────────────────────────────────────────────────────

log "Committing release"
git add package.json package-lock.json CHANGELOG.md
git commit -m "chore(release): $TAG [skip ci]"
ok "Release commit created"

# ─── 10. tag ────────────────────────────────────────────────────────────────

git tag "$TAG"
ok "Tag created: $TAG"

# ─── 11. push ───────────────────────────────────────────────────────────────

log "Pushing to origin"
git push origin main --follow-tags
ok "Pushed"

# ─── 12. github release (warn-only) ─────────────────────────────────────────
# If this fails, npm is already published and git is pushed.
# Consumers are unaffected — the release can be created manually.

log "Creating GitHub Release"

NOTES_FILE=$(mktemp)
echo "$GITHUB_CHANGELOG" > "$NOTES_FILE"

if ! gh release create "$TAG" \
  --title "$TAG" \
  --notes-file "$NOTES_FILE" \
  --target main; then
  rm -f "$NOTES_FILE"
  log "⚠ GitHub Release failed — npm is published, create it manually"
else
  rm -f "$NOTES_FILE"
  ok "GitHub Release created: $TAG"
fi

set_output "released" "true"
set_output "version" "$TAG"

# ─── 13. step summary ───────────────────────────────────────────────────────

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  PKG_NAME=$(jq -r .name package.json)
  REPO_NAME=$(basename "$REPO_URL")

  cat >> "$GITHUB_STEP_SUMMARY" <<MD
## \`${PKG_NAME}@${VERSION}\` published 🚀

| | |
|---|---|
| Version | [\`${TAG}\`](${REPO_URL}/releases/tag/${TAG}) |
| Package | [GitHub Packages](${REPO_URL}/pkgs/npm/${REPO_NAME}) |
MD
  ok "Step summary written"
fi