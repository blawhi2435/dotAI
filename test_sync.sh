#!/bin/bash
# test_sync.sh — integration tests for sync.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC="$SCRIPT_DIR/sync.sh"
PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { PASS=$((PASS+1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}✗${NC} $1"; }

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

new_test() {
    echo ""
    echo -e "${YELLOW}── $1${NC}"
    TEST_DIR="$(mktemp -d)"
    FAKE_REPO="$TEST_DIR/repo"
    FAKE_CLAUDE="$TEST_DIR/claude"
    mkdir -p "$FAKE_REPO/plugins"
    mkdir -p "$FAKE_CLAUDE"
    export DOTAI_REPO_DIR="$FAKE_REPO"
    export DOTAI_CLAUDE_DIR="$FAKE_CLAUDE"
}

cleanup() {
    rm -rf "$TEST_DIR"
    unset DOTAI_REPO_DIR DOTAI_CLAUDE_DIR
}

run() {
    OUTPUT=$("$SYNC" "$@" 2>&1) || true
}

# ---------------------------------------------------------------------------
# 5.1 — sync to --overwrite
# ---------------------------------------------------------------------------
new_test "5.1 — sync to --overwrite"

mkdir -p "$FAKE_REPO/skills/myskill"
echo "skill content" > "$FAKE_REPO/skills/myskill/SKILL.md"
mkdir -p "$FAKE_REPO/commands"
echo "cmd content" > "$FAKE_REPO/commands/test.md"
mkdir -p "$FAKE_REPO/hooks"
echo "hook content" > "$FAKE_REPO/hooks/post-tool-use.sh"
mkdir -p "$FAKE_REPO/rules"
echo "rule content" > "$FAKE_REPO/rules/main.md"
echo '{"model": "claude-sonnet"}' > "$FAKE_REPO/settings.json"
echo '["plugin-a@official"]' > "$FAKE_REPO/plugins/whitelist.json"

# Pre-existing in ~/.claude (should be backed up)
mkdir -p "$FAKE_CLAUDE/skills/oldskill"
echo "old skill" > "$FAKE_CLAUDE/skills/oldskill/SKILL.md"
echo '{"old_key": "old_val"}' > "$FAKE_CLAUDE/settings.json"

run to --overwrite

[ -f "$FAKE_CLAUDE/skills/myskill/SKILL.md" ]       && ok "skills copied"       || fail "skills not copied"
[ -f "$FAKE_CLAUDE/commands/test.md" ]               && ok "commands copied"     || fail "commands not copied"
[ -f "$FAKE_CLAUDE/hooks/post-tool-use.sh" ]         && ok "hooks copied"        || fail "hooks not copied"
[ -f "$FAKE_CLAUDE/rules/main.md" ]                  && ok "rules copied"        || fail "rules not copied"
[ -f "$FAKE_CLAUDE/settings.json" ]                  && ok "settings.json copied" || fail "settings.json not copied"
[ -d "$FAKE_CLAUDE/skills.bak" ]                     && ok "skills.bak created"  || fail "skills.bak not created"
[ -f "$FAKE_CLAUDE/skills.bak/oldskill/SKILL.md" ]   && ok "skills.bak content"  || fail "skills.bak content missing"
[ -f "$FAKE_CLAUDE/settings.json.bak" ]              && ok "settings.json.bak"   || fail "settings.json.bak missing"
[ ! -d "$FAKE_CLAUDE/skills/oldskill" ]              && ok "old skill removed (--delete)" || fail "old skill still present"
echo "$OUTPUT" | grep -q "plugin-a@official"         && ok "plugin prompt shown" || fail "plugin prompt missing"

cleanup

# ---------------------------------------------------------------------------
# 5.1 — legacy symlink removal
# ---------------------------------------------------------------------------
new_test "5.1 — legacy symlink removal"

mkdir -p "$FAKE_REPO/skills/myskill"
echo "skill" > "$FAKE_REPO/skills/myskill/SKILL.md"
echo '{}'  > "$FAKE_REPO/settings.json"
echo '[]'  > "$FAKE_REPO/plugins/whitelist.json"

ln -s "$FAKE_REPO/skills" "$FAKE_CLAUDE/skills"

run to --overwrite

[ ! -L "$FAKE_CLAUDE/skills" ]   && ok "legacy symlink removed"      || fail "legacy symlink still exists"
[ -d "$FAKE_CLAUDE/skills" ]     && ok "skills dir recreated"        || fail "skills dir not recreated"
[ ! -e "$FAKE_CLAUDE/skills.bak" ] && ok "no .bak for legacy symlink" || fail ".bak created for legacy symlink"

cleanup

# ---------------------------------------------------------------------------
# 5.1 — previous .bak overwritten
# ---------------------------------------------------------------------------
new_test "5.1 — previous .bak is overwritten"

mkdir -p "$FAKE_REPO/skills/new"
echo "new" > "$FAKE_REPO/skills/new/SKILL.md"
echo '{}' > "$FAKE_REPO/settings.json"
echo '[]' > "$FAKE_REPO/plugins/whitelist.json"

# First run: creates skills.bak from "first"
mkdir -p "$FAKE_CLAUDE/skills/first"
echo "first" > "$FAKE_CLAUDE/skills/first/SKILL.md"
run to --overwrite

# Second run: skills.bak should now contain "new", not "first"
mkdir -p "$FAKE_CLAUDE/skills/second"
echo "second" > "$FAKE_CLAUDE/skills/second/SKILL.md"
run to --overwrite

[ -f "$FAKE_CLAUDE/skills.bak/second/SKILL.md" ] && ok ".bak overwritten with latest" || fail ".bak not updated"
[ ! -f "$FAKE_CLAUDE/skills.bak/first/SKILL.md" ] && ok "previous .bak content gone"  || fail "previous .bak leaked"

cleanup

# ---------------------------------------------------------------------------
# 5.2 — sync to --merge
# ---------------------------------------------------------------------------
new_test "5.2 — sync to --merge (directories)"

mkdir -p "$FAKE_REPO/skills/skillA"
echo "A from repo" > "$FAKE_REPO/skills/skillA/SKILL.md"
mkdir -p "$FAKE_REPO/skills/skillB"
echo "B from repo" > "$FAKE_REPO/skills/skillB/SKILL.md"
echo '{}' > "$FAKE_REPO/settings.json"
echo '[]' > "$FAKE_REPO/plugins/whitelist.json"

# ~/.claude already has skillA with different content
mkdir -p "$FAKE_CLAUDE/skills/skillA"
echo "A original" > "$FAKE_CLAUDE/skills/skillA/SKILL.md"

run to --merge

[ "$(cat "$FAKE_CLAUDE/skills/skillA/SKILL.md")" = "A original" ] && ok "existing skill preserved" || fail "existing skill overwritten"
[ -f "$FAKE_CLAUDE/skills/skillB/SKILL.md" ]                      && ok "new skill added"         || fail "new skill not added"
[ "$(cat "$FAKE_CLAUDE/skills/skillB/SKILL.md")" = "B from repo" ] && ok "new skill correct content" || fail "new skill wrong content"
[ ! -e "$FAKE_CLAUDE/skills.bak" ]                                && ok "no backup in merge mode"  || fail "unexpected backup"

cleanup

new_test "5.2 — sync to --merge (settings.json key-level)"

echo '{"model": "claude-sonnet", "new_key": "new_val", "nested": {"a": 1, "b": 2}}' > "$FAKE_REPO/settings.json"
echo '[]' > "$FAKE_REPO/plugins/whitelist.json"
echo '{"model": "claude-opus", "existing": "keep", "nested": {"a": 99, "c": 3}}' > "$FAKE_CLAUDE/settings.json"

run to --merge

# Existing top-level keys: preserved
grep -q '"model": "claude-opus"'   "$FAKE_CLAUDE/settings.json" && ok "model key preserved"      || fail "model overwritten"
grep -q '"existing": "keep"'       "$FAKE_CLAUDE/settings.json" && ok "existing key preserved"   || fail "existing key lost"

# New top-level key: added
grep -q '"new_key": "new_val"'     "$FAKE_CLAUDE/settings.json" && ok "new_key added"            || fail "new_key missing"

# Nested: existing nested key preserved, new nested key added
grep -q '"a": 99'                  "$FAKE_CLAUDE/settings.json" && ok "nested.a preserved (99)"  || fail "nested.a overwritten"
grep -q '"c": 3'                   "$FAKE_CLAUDE/settings.json" && ok "nested.c added"           || fail "nested.c missing"
grep -q '"b": 2'                   "$FAKE_CLAUDE/settings.json" && ok "nested.b added"           || fail "nested.b missing"

cleanup

new_test "5.2 — sync to --merge (settings.json missing at target)"

echo '{"key": "val"}' > "$FAKE_REPO/settings.json"
echo '[]' > "$FAKE_REPO/plugins/whitelist.json"
# No settings.json in ~/.claude

run to --merge

[ -f "$FAKE_CLAUDE/settings.json" ]                && ok "settings.json created" || fail "settings.json not created"
grep -q '"key": "val"' "$FAKE_CLAUDE/settings.json" && ok "content correct"      || fail "content wrong"

cleanup

# ---------------------------------------------------------------------------
# 5.3 — sync from --overwrite
# ---------------------------------------------------------------------------
new_test "5.3 — sync from --overwrite"

mkdir -p "$FAKE_CLAUDE/skills/userSkill"
echo "user skill" > "$FAKE_CLAUDE/skills/userSkill/SKILL.md"
echo '{"user_key": "user_val"}' > "$FAKE_CLAUDE/settings.json"

# Pre-existing in repo (should be backed up)
mkdir -p "$FAKE_REPO/skills/repoSkill"
echo "repo skill" > "$FAKE_REPO/skills/repoSkill/SKILL.md"
echo '{"repo_key": "repo_val"}' > "$FAKE_REPO/settings.json"
echo '[]' > "$FAKE_REPO/plugins/whitelist.json"

run from --overwrite

[ -f "$FAKE_REPO/skills/userSkill/SKILL.md" ]       && ok "user skill copied to repo"     || fail "user skill not in repo"
[ -d "$FAKE_REPO/skills.bak" ]                      && ok "repo skills.bak created"       || fail "repo skills.bak missing"
[ -f "$FAKE_REPO/skills.bak/repoSkill/SKILL.md" ]   && ok "skills.bak has old content"    || fail "skills.bak content wrong"
[ ! -d "$FAKE_REPO/skills/repoSkill" ]              && ok "old repo skill removed"        || fail "old repo skill present"
grep -q '"user_key"' "$FAKE_REPO/settings.json"     && ok "settings.json overwritten"     || fail "settings.json not overwritten"
echo "$OUTPUT" | grep -q "Plugin setup" \
    && fail "plugin prompt shown for 'from'" \
    || ok "no plugin prompt for 'from'"

cleanup

# ---------------------------------------------------------------------------
# 5.4 — sync from --merge
# ---------------------------------------------------------------------------
new_test "5.4 — sync from --merge"

mkdir -p "$FAKE_CLAUDE/skills/skillC"
echo "C content" > "$FAKE_CLAUDE/skills/skillC/SKILL.md"
echo '{"claude_key": "claude_val", "shared": "claude_wins"}' > "$FAKE_CLAUDE/settings.json"

mkdir -p "$FAKE_REPO/skills/skillD"
echo "D content" > "$FAKE_REPO/skills/skillD/SKILL.md"
echo '{"repo_key": "repo_val", "shared": "repo_wins"}' > "$FAKE_REPO/settings.json"
echo '[]' > "$FAKE_REPO/plugins/whitelist.json"

run from --merge

[ -f "$FAKE_REPO/skills/skillD/SKILL.md" ]         && ok "existing repo skill preserved"       || fail "repo skill lost"
[ -f "$FAKE_REPO/skills/skillC/SKILL.md" ]         && ok "new skill merged into repo"          || fail "new skill not merged"
grep -q '"repo_key": "repo_val"' "$FAKE_REPO/settings.json"  && ok "repo key preserved"        || fail "repo key lost"
grep -q '"shared": "repo_wins"' "$FAKE_REPO/settings.json"   && ok "shared key: repo wins"     || fail "shared key overwritten"
grep -q '"claude_key": "claude_val"' "$FAKE_REPO/settings.json" && ok "claude-only key added"  || fail "claude key not added"

cleanup

# ---------------------------------------------------------------------------
# 5.5 — Idempotency
# ---------------------------------------------------------------------------
new_test "5.5 — idempotency"

mkdir -p "$FAKE_REPO/skills/myskill"
echo "content" > "$FAKE_REPO/skills/myskill/SKILL.md"
echo '{"key": "val"}' > "$FAKE_REPO/settings.json"
echo '[]' > "$FAKE_REPO/plugins/whitelist.json"

# Overwrite twice — content unchanged
run to --overwrite
FIRST="$(cat "$FAKE_CLAUDE/skills/myskill/SKILL.md")"
run to --overwrite
SECOND="$(cat "$FAKE_CLAUDE/skills/myskill/SKILL.md")"
[ "$FIRST" = "$SECOND" ] && ok "overwrite: content stable after re-run" || fail "overwrite: content changed"

# Merge twice — local additions survive both runs
echo "local" > "$FAKE_CLAUDE/skills/myskill/local.md"
run to --merge
[ -f "$FAKE_CLAUDE/skills/myskill/local.md" ] && ok "merge: local file survives first run"  || fail "merge: local file lost"
run to --merge
[ -f "$FAKE_CLAUDE/skills/myskill/local.md" ] && ok "merge: local file survives second run" || fail "merge: local file lost on re-run"

cleanup

# ---------------------------------------------------------------------------
# 5.6 — Edge cases
# ---------------------------------------------------------------------------
new_test "5.6 — empty whitelist"

echo '{}' > "$FAKE_REPO/settings.json"
echo '[]' > "$FAKE_REPO/plugins/whitelist.json"

run to --overwrite
echo "$OUTPUT" | grep -q "Plugin setup" \
    && fail "plugin prompt shown for empty whitelist" \
    || ok "no prompt for empty whitelist"

cleanup

new_test "5.6 — missing source items skipped"

# ~/.claude has only skills; commands/hooks/rules/settings missing
mkdir -p "$FAKE_CLAUDE/skills/onlySkill"
echo "only" > "$FAKE_CLAUDE/skills/onlySkill/SKILL.md"

# Repo has commands that should be untouched (source missing → skip)
mkdir -p "$FAKE_REPO/commands"
echo "keep" > "$FAKE_REPO/commands/keep.md"
echo '[]' > "$FAKE_REPO/plugins/whitelist.json"

run from --overwrite

[ -f "$FAKE_REPO/skills/onlySkill/SKILL.md" ] && ok "available source copied"           || fail "source item not copied"
[ -f "$FAKE_REPO/commands/keep.md" ]          && ok "missing source → target untouched" || fail "commands unexpectedly modified"

cleanup

new_test "5.6 — no whitelist.json file"

echo '{}' > "$FAKE_REPO/settings.json"
rm -f "$FAKE_REPO/plugins/whitelist.json"

run to --overwrite
echo "$OUTPUT" | grep -q "Plugin setup" \
    && fail "plugin prompt shown with no whitelist file" \
    || ok "no prompt when whitelist.json missing"

cleanup

# ---------------------------------------------------------------------------
# 6.1 — plugin state: sync from --overwrite
# ---------------------------------------------------------------------------
new_test "6.1 — plugin state: sync from --overwrite"

mkdir -p "$FAKE_CLAUDE/plugins/cache/official/myplugin"
echo "plugin code" > "$FAKE_CLAUDE/plugins/cache/official/myplugin/index.js"
mkdir -p "$FAKE_CLAUDE/plugins/marketplaces/official"
echo "marketplace" > "$FAKE_CLAUDE/plugins/marketplaces/official/README.md"
echo '{"version":2,"plugins":{"myplugin@official":[{"scope":"user"}]}}' > "$FAKE_CLAUDE/plugins/installed_plugins.json"
echo '{"official":{"source":{"source":"github","repo":"test/official"}}}' > "$FAKE_CLAUDE/plugins/known_marketplaces.json"

# whitelist in repo must survive
echo '["keep-me@marketplace"]' > "$FAKE_REPO/plugins/whitelist.json"

run from --overwrite

[ -f "$FAKE_REPO/plugins/cache/official/myplugin/index.js" ]        && ok "cache/ copied to repo"                    || fail "cache/ not copied"
[ -f "$FAKE_REPO/plugins/marketplaces/official/README.md" ]         && ok "marketplaces/ copied to repo"            || fail "marketplaces/ not copied"
[ -f "$FAKE_REPO/plugins/installed_plugins.json" ]                  && ok "installed_plugins.json copied"           || fail "installed_plugins.json not copied"
[ -f "$FAKE_REPO/plugins/known_marketplaces.json" ]                 && ok "known_marketplaces.json copied"          || fail "known_marketplaces.json not copied"
grep -q "myplugin@official" "$FAKE_REPO/plugins/installed_plugins.json" && ok "installed_plugins.json content ok"   || fail "installed_plugins.json content wrong"
[ -f "$FAKE_REPO/plugins/whitelist.json" ]                          && ok "whitelist.json still exists"             || fail "whitelist.json deleted"
grep -q "keep-me@marketplace" "$FAKE_REPO/plugins/whitelist.json"   && ok "whitelist.json content unchanged"        || fail "whitelist.json content changed"

cleanup

# ---------------------------------------------------------------------------
# 6.2 — plugin state: sync to --overwrite
# ---------------------------------------------------------------------------
new_test "6.2 — plugin state: sync to --overwrite"

mkdir -p "$FAKE_REPO/plugins/cache/official/myplugin"
echo "plugin code" > "$FAKE_REPO/plugins/cache/official/myplugin/index.js"
mkdir -p "$FAKE_REPO/plugins/marketplaces/official"
echo "marketplace" > "$FAKE_REPO/plugins/marketplaces/official/README.md"
echo '{"version":2,"plugins":{"myplugin@official":[{"scope":"user"}]}}' > "$FAKE_REPO/plugins/installed_plugins.json"
echo '{"official":{"source":{"source":"github","repo":"test/official"}}}' > "$FAKE_REPO/plugins/known_marketplaces.json"
echo '["keep-me@marketplace"]' > "$FAKE_REPO/plugins/whitelist.json"
echo '{}' > "$FAKE_REPO/settings.json"

run to --overwrite

[ -f "$FAKE_CLAUDE/plugins/cache/official/myplugin/index.js" ]   && ok "cache/ restored to ~/.claude"              || fail "cache/ not restored"
[ -f "$FAKE_CLAUDE/plugins/marketplaces/official/README.md" ]    && ok "marketplaces/ restored"                   || fail "marketplaces/ not restored"
[ -f "$FAKE_CLAUDE/plugins/installed_plugins.json" ]             && ok "installed_plugins.json restored"          || fail "installed_plugins.json not restored"
[ -f "$FAKE_CLAUDE/plugins/known_marketplaces.json" ]            && ok "known_marketplaces.json restored"         || fail "known_marketplaces.json not restored"
[ ! -f "$FAKE_CLAUDE/plugins/whitelist.json" ]                   && ok "whitelist.json NOT copied to ~/.claude"   || fail "whitelist.json leaked into ~/.claude"

cleanup

# ---------------------------------------------------------------------------
# 6.3 — plugin state: sync from --merge
# ---------------------------------------------------------------------------
new_test "6.3 — plugin state: sync from --merge"

# ~/.claude has plugin state
mkdir -p "$FAKE_CLAUDE/plugins/cache/official/pluginA"
echo "A code" > "$FAKE_CLAUDE/plugins/cache/official/pluginA/index.js"
echo '{"version":2,"plugins":{"pluginA@official":[{"scope":"user"}],"pluginB@official":[{"scope":"user"}]}}' > "$FAKE_CLAUDE/plugins/installed_plugins.json"

# repo already has some plugin state — must be preserved in merge
mkdir -p "$FAKE_REPO/plugins/cache/official/pluginB"
echo "B code" > "$FAKE_REPO/plugins/cache/official/pluginB/index.js"
echo '{"version":2,"plugins":{"pluginB@official":[{"scope":"user","existing":true}]}}' > "$FAKE_REPO/plugins/installed_plugins.json"
echo '["keep"]' > "$FAKE_REPO/plugins/whitelist.json"

run from --merge

[ -f "$FAKE_REPO/plugins/cache/official/pluginA/index.js" ]           && ok "merge: new cache added"                  || fail "merge: new cache missing"
[ -f "$FAKE_REPO/plugins/cache/official/pluginB/index.js" ]           && ok "merge: existing cache preserved"         || fail "merge: existing cache lost"
grep -q '"existing": true' "$FAKE_REPO/plugins/installed_plugins.json" && ok "merge: existing JSON key preserved"     || fail "merge: existing key overwritten"
grep -q "pluginA@official" "$FAKE_REPO/plugins/installed_plugins.json" && ok "merge: new JSON key added"              || fail "merge: new key not added"
[ -f "$FAKE_REPO/plugins/whitelist.json" ]                            && ok "merge: whitelist.json untouched"         || fail "merge: whitelist.json affected"

cleanup

# ---------------------------------------------------------------------------
# 6.4 — plugin state: missing source items skipped
# ---------------------------------------------------------------------------
new_test "6.4 — plugin state: missing source items skipped gracefully"

# ~/.claude/plugins/ exists but has no plugin state files or dirs
mkdir -p "$FAKE_CLAUDE/plugins"
echo '[]' > "$FAKE_REPO/plugins/whitelist.json"
echo '{}' > "$FAKE_REPO/settings.json"

run from --overwrite

echo "$OUTPUT" | grep -q "source missing, skipped" && ok "missing items produce skip notice" || fail "no skip notice for missing items"

cleanup

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS+FAIL))
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}All $TOTAL tests passed${NC}"
else
    echo -e "${RED}$FAIL / $TOTAL tests failed${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ $FAIL -eq 0 ] || exit 1
