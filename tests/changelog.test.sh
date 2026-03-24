#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/changelog.sh"

PASS=0
FAIL=0
TESTS=0

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  TESTS=$((TESTS + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  ✔ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✖ $label"
    echo "    expected to contain: $needle"
    echo "    got: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  TESTS=$((TESTS + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ✔ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✖ $label"
    echo "    expected NOT to contain: $needle"
    FAIL=$((FAIL + 1))
  fi
}

# ─── Fixtures ────────────────────────────────────────────────────────────────

TAB=$'\t'
REPO="https://github.com/armadillo-ui/math-utils"

COMMITS_MIXED="abc123full${TAB}abc1234${TAB}feat: add multiply function${TAB}Alice
def456full${TAB}def4567${TAB}fix: handle division by zero${TAB}Bob
ghi789full${TAB}ghi7890${TAB}docs: update README${TAB}Alice"

COMMITS_FEAT_ONLY="abc123full${TAB}abc1234${TAB}feat(math): add subtract${TAB}Charlie"

COMMITS_FIX_SCOPED="xyz999full${TAB}xyz9999${TAB}fix(core): null pointer${TAB}Dana"

COMMITS_BREAKING="brk000full${TAB}brk0000${TAB}feat!: redesign API${TAB}Eve"

# ─── Tests ───────────────────────────────────────────────────────────────────

echo "generate_changelog_entry"

echo "  with mixed commit types:"
result=$(generate_changelog_entry "v1.0.0" "v0.9.0" "$REPO" "true" "$COMMITS_MIXED")

assert_contains "header has tag with compare link" "$result" \
  "## [v1.0.0]($REPO/compare/v0.9.0..v1.0.0)"

assert_contains "has Features section" "$result" "### Features"
assert_contains "has Bug fixes section" "$result" "### Bug fixes"
assert_contains "has Documentation section" "$result" "### Documentation"

assert_contains "feat entry has commit link" "$result" \
  "- add multiply function - ([abc1234]($REPO/commit/abc123full))"

assert_contains "fix entry has commit link" "$result" \
  "- handle division by zero - ([def4567]($REPO/commit/def456full))"

assert_contains "docs entry has commit link" "$result" \
  "- update README - ([ghi7890]($REPO/commit/ghi789full))"

assert_not_contains "no feat: prefix in output" "$result" "- feat:"
assert_not_contains "no fix: prefix in output" "$result" "- fix:"

echo ""
echo "  with scoped feat commit:"
result=$(generate_changelog_entry "v2.0.0" "v1.0.0" "$REPO" "true" "$COMMITS_FEAT_ONLY")

assert_contains "strips scope from prefix" "$result" \
  "- add subtract - ([abc1234]($REPO/commit/abc123full))"
assert_not_contains "no feat(math): in output" "$result" "feat(math):"

echo ""
echo "  with scoped fix commit:"
result=$(generate_changelog_entry "v1.0.1" "v1.0.0" "$REPO" "true" "$COMMITS_FIX_SCOPED")

assert_contains "strips scoped fix prefix" "$result" \
  "- null pointer - ([xyz9999]($REPO/commit/xyz999full))"

echo ""
echo "  with breaking change commit:"
result=$(generate_changelog_entry "v2.0.0" "v1.0.0" "$REPO" "true" "$COMMITS_BREAKING")

assert_contains "strips breaking prefix" "$result" \
  "- redesign API - ([brk0000]($REPO/commit/brk000full))"

echo ""
echo "  without previous tag:"
result=$(generate_changelog_entry "v0.1.0" "v0.0.0" "$REPO" "false" "$COMMITS_FEAT_ONLY")

assert_contains "header has no compare link" "$result" "## v0.1.0 -"
assert_not_contains "no compare URL" "$result" "/compare/"

echo ""
echo "  section ordering:"
result=$(generate_changelog_entry "v1.0.0" "v0.9.0" "$REPO" "true" "$COMMITS_MIXED")
feat_pos=$(echo "$result" | grep -n "### Features" | head -1 | cut -d: -f1)
fix_pos=$(echo "$result" | grep -n "### Bug fixes" | head -1 | cut -d: -f1)
docs_pos=$(echo "$result" | grep -n "### Documentation" | head -1 | cut -d: -f1)

TESTS=$((TESTS + 1))
if [[ "$feat_pos" -lt "$fix_pos" && "$fix_pos" -lt "$docs_pos" ]]; then
  echo "  ✔ sections in order: Features < Bug fixes < Documentation"
  PASS=$((PASS + 1))
else
  echo "  ✖ sections not in expected order"
  FAIL=$((FAIL + 1))
fi

# ─── insert_changelog_entry ──────────────────────────────────────────────────

echo ""
echo "insert_changelog_entry"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "  inserts after first separator:"
cat > "$TMPDIR_TEST/CHANGELOG.md" <<'EOF'
# Changelog
All notable changes will be documented here.

- - -
## [v0.9.0](https://example.com/compare/v0.8.0..v0.9.0) - 2026-01-01
### Features
- old feature - ([aaa1111](https://example.com/commit/aaa)) - OldAuthor

- - -
EOF

ENTRY="## [v1.0.0](https://example.com/compare/v0.9.0..v1.0.0) - 2026-03-24
### Features
- new feature - ([bbb2222](https://example.com/commit/bbb)) - NewAuthor"

insert_changelog_entry "$ENTRY" "$TMPDIR_TEST/CHANGELOG.md"
inserted=$(cat "$TMPDIR_TEST/CHANGELOG.md")

assert_contains "header still at top" "$inserted" "# Changelog"

# Check that new entry comes before old entry
new_pos=$(echo "$inserted" | grep -n "new feature" | head -1 | cut -d: -f1)
old_pos=$(echo "$inserted" | grep -n "old feature" | head -1 | cut -d: -f1)

TESTS=$((TESTS + 1))
if [[ "$new_pos" -lt "$old_pos" ]]; then
  echo "  ✔ new entry inserted before old entry"
  PASS=$((PASS + 1))
else
  echo "  ✖ new entry not before old entry (new=$new_pos, old=$old_pos)"
  FAIL=$((FAIL + 1))
fi

assert_contains "original header preserved" "$inserted" "All notable changes"

echo ""
echo "  creates file if not exists:"
rm -f "$TMPDIR_TEST/NEW.md"
insert_changelog_entry "$ENTRY" "$TMPDIR_TEST/NEW.md"
created=$(cat "$TMPDIR_TEST/NEW.md")

assert_contains "file created with entry" "$created" "## [v1.0.0]"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS/$TESTS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
