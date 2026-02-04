#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# dotAI sync — bidirectional sync of managed .claude config
# ---------------------------------------------------------------------------
# Usage:
#   sync.sh to   --overwrite   Sync repo → ~/.claude (backup & replace)
#   sync.sh to   --merge       Sync repo → ~/.claude (add missing only)
#   sync.sh from --overwrite   Sync ~/.claude → repo  (backup & replace)
#   sync.sh from --merge       Sync ~/.claude → repo  (add missing only)
#   sync.sh --help
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Path resolution — follows symlinks so repo can live anywhere
# ---------------------------------------------------------------------------
_script="$0"
while [ -L "$_script" ]; do
    _dir="$(cd "$(dirname "$_script")" && pwd)"
    _script="$_dir/$(readlink "$_script")"
done
_resolved_repo="$(cd "$(dirname "$_script")" && pwd)"

# Allow env override for testing
REPO_DIR="${DOTAI_REPO_DIR:-$_resolved_repo}"
CLAUDE_DIR="${DOTAI_CLAUDE_DIR:-$HOME/.claude}"

# Backup directory with date
BACKUP_DATE="$(date +%Y-%m-%d)"
BACKUP_DIR="$REPO_DIR/.dotai.back/$BACKUP_DATE"

# ---------------------------------------------------------------------------
# Managed items
# ---------------------------------------------------------------------------
MANAGED_DIRS=("skills" "commands" "hooks" "rules")
MANAGED_FILES=("settings.json")
PLUGIN_STATE_FILES=("installed_plugins.json" "known_marketplaces.json")

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
dotAI sync — bidirectional .claude config sync

Usage:
  $(basename "$0") to   --overwrite   Sync repo → ~/.claude (backup & replace)
  $(basename "$0") to   --merge       Sync repo → ~/.claude (add missing only)
  $(basename "$0") from --overwrite   Sync ~/.claude → repo  (backup & replace)
  $(basename "$0") from --merge       Sync ~/.claude → repo  (add missing only)
  $(basename "$0") --help             Show this help
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
case "$1" in
    to|from) DIRECTION="$1" ;;
    --help|-h) usage; exit 0 ;;
    *) usage; exit 1 ;;
esac

case "$2" in
    --overwrite) STRATEGY="overwrite" ;;
    --merge)     STRATEGY="merge"     ;;
    *)           usage; exit 1        ;;
esac

# ---------------------------------------------------------------------------
# Derive source and target
# ---------------------------------------------------------------------------
if [ "$DIRECTION" = "to" ]; then
    SRC="$REPO_DIR"
    TGT="$CLAUDE_DIR"
else
    SRC="$CLAUDE_DIR"
    TGT="$REPO_DIR"
fi

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

# ensure_gitignore_entry
# Ensures .dotai.back/ is in .gitignore. Creates .gitignore if it doesn't exist.
ensure_gitignore_entry() {
    local gitignore="$REPO_DIR/.gitignore"
    local entry=".dotai.back/"

    if [ ! -f "$gitignore" ]; then
        echo "$entry" > "$gitignore"
        return
    fi

    if ! grep -qxF "$entry" "$gitignore"; then
        echo "$entry" >> "$gitignore"
    fi
}

# backup_target <path> <relative_path>
# Copies <path> to $BACKUP_DIR/<relative_path>.bak. Overwrites previous backup if present.
# <relative_path> preserves directory structure (e.g., "plugins/installed_plugins.json")
backup_target() {
    local tgt="$1"
    local rel_path="$2"
    local bak="$BACKUP_DIR/${rel_path}.bak"
    local bak_dir
    bak_dir="$(dirname "$bak")"

    # Ensure .gitignore has .dotai.back/ entry
    ensure_gitignore_entry

    # Create backup directory structure
    mkdir -p "$bak_dir"

    # Remove existing backup if present
    if [ -e "$bak" ] || [ -L "$bak" ]; then
        rm -rf "$bak"
    fi

    # Copy to backup location (use cp to avoid cross-device issues)
    cp -R "$tgt" "$bak"
    echo "  ↳ backed up to .dotai.back/$BACKUP_DATE/${rel_path}.bak"
}

# is_legacy_symlink <path>
# Returns 0 if <path> is a symlink pointing into this repo (created by old setup.sh)
is_legacy_symlink() {
    local path="$1"
    [ -L "$path" ] || return 1
    local target
    target="$(readlink "$path")"
    case "$target" in
        "$REPO_DIR"/*|"$REPO_DIR") return 0 ;;
    esac
    return 1
}

# sync_directory_overwrite <src> <tgt> <rel_path>
# Backs up tgt, then makes tgt an exact copy of src.
# <rel_path> is the relative path for backup (e.g., "skills" or "plugins/cache")
sync_directory_overwrite() {
    local src="$1" tgt="$2" rel_path="$3" name
    name="$(basename "$tgt")"

    if [ ! -d "$src" ]; then
        echo "  ⊘ $name — source missing, skipped"
        return
    fi

    if is_legacy_symlink "$tgt"; then
        rm -f "$tgt"
        echo "  ↳ removed legacy symlink"
    elif [ -e "$tgt" ] || [ -L "$tgt" ]; then
        backup_target "$tgt" "$rel_path"
    fi

    mkdir -p "$tgt"
    rsync -a --delete "$src/" "$tgt/"
    echo "  ✓ $name"
}

# sync_directory_merge <src> <tgt>
# Copies files from src that don't exist in tgt. Existing files untouched.
sync_directory_merge() {
    local src="$1" tgt="$2" name
    name="$(basename "$tgt")"

    if [ ! -d "$src" ]; then
        echo "  ⊘ $name — source missing, skipped"
        return
    fi

    mkdir -p "$tgt"
    rsync -a --ignore-existing "$src/" "$tgt/"
    echo "  ✓ $name (merged)"
}

# merge_json <src> <tgt>
# Deep-merges: adds keys from src that are missing in tgt at any depth.
# All existing keys in tgt are preserved unchanged.
merge_json() {
    local src="$1" tgt="$2" name
    name="$(basename "$tgt")"

    if [ ! -f "$src" ]; then
        echo "  ⊘ $name — source missing, skipped"
        return
    fi

    if [ ! -f "$tgt" ]; then
        cp "$src" "$tgt"
        echo "  ✓ $name (copied)"
        return
    fi

    if ! command -v python3 &>/dev/null; then
        echo "  ✗ $name — python3 required for JSON merge but not found"
        echo "    Install: xcode-select --install"
        exit 1
    fi

    python3 - "$src" "$tgt" <<'PYTHON'
import json, sys

def deep_merge(base, overlay):
    """Return base with missing keys filled in from overlay."""
    result = dict(base)
    for key, val in overlay.items():
        if key not in result:
            result[key] = val
        elif isinstance(result[key], dict) and isinstance(val, dict):
            result[key] = deep_merge(result[key], val)
    return result

src_path, tgt_path = sys.argv[1], sys.argv[2]

with open(tgt_path) as f:
    target = json.load(f)
with open(src_path) as f:
    source = json.load(f)

merged = deep_merge(target, source)

with open(tgt_path, 'w') as f:
    json.dump(merged, f, indent=2)
    f.write('\n')
PYTHON
    echo "  ✓ $name (merged)"
}

# parameterize_plugin_paths <src> <tgt> <claude_dir>
# Copies JSON from src to tgt, replacing $claude_dir paths with $CLAUDE_HOME
parameterize_plugin_paths() {
    local src="$1" tgt="$2" claude_dir="$3" name
    name="$(basename "$tgt")"

    if [ ! -f "$src" ]; then
        echo "  ⊘ $name — source missing, skipped"
        return
    fi

    if ! command -v python3 &>/dev/null; then
        echo "  ✗ $name — python3 required but not found"
        exit 1
    fi

    python3 - "$src" "$tgt" "$claude_dir" <<'PYTHON'
import json, sys

src_path, tgt_path, claude_dir = sys.argv[1], sys.argv[2], sys.argv[3]

with open(src_path) as f:
    content = f.read()

# Replace absolute claude_dir paths with $CLAUDE_HOME
content = content.replace(claude_dir, '$CLAUDE_HOME')

with open(tgt_path, 'w') as f:
    f.write(content)
PYTHON
    echo "  ✓ $name (paths parameterized)"
}

# expand_plugin_paths <src> <tgt> <claude_dir>
# Copies JSON from src to tgt, replacing $CLAUDE_HOME with $claude_dir
expand_plugin_paths() {
    local src="$1" tgt="$2" claude_dir="$3" name
    name="$(basename "$tgt")"

    if [ ! -f "$src" ]; then
        echo "  ⊘ $name — source missing, skipped"
        return
    fi

    if ! command -v python3 &>/dev/null; then
        echo "  ✗ $name — python3 required but not found"
        exit 1
    fi

    python3 - "$src" "$tgt" "$claude_dir" <<'PYTHON'
import json, sys

src_path, tgt_path, claude_dir = sys.argv[1], sys.argv[2], sys.argv[3]

with open(src_path) as f:
    content = f.read()

# Replace $CLAUDE_HOME with the target environment's absolute path
content = content.replace('$CLAUDE_HOME', claude_dir)

with open(tgt_path, 'w') as f:
    f.write(content)
PYTHON
    echo "  ✓ $name (paths expanded)"
}

# merge_plugin_json <src> <tgt> <direction> <claude_dir>
# Deep-merges JSON with path transformation based on direction
merge_plugin_json() {
    local src="$1" tgt="$2" direction="$3" claude_dir="$4" name
    name="$(basename "$tgt")"

    if [ ! -f "$src" ]; then
        echo "  ⊘ $name — source missing, skipped"
        return
    fi

    if ! command -v python3 &>/dev/null; then
        echo "  ✗ $name — python3 required but not found"
        exit 1
    fi

    # If target doesn't exist, just transform and copy
    if [ ! -f "$tgt" ]; then
        if [ "$direction" = "from" ]; then
            parameterize_plugin_paths "$src" "$tgt" "$claude_dir"
        else
            expand_plugin_paths "$src" "$tgt" "$claude_dir"
        fi
        return
    fi

    python3 - "$src" "$tgt" "$direction" "$claude_dir" <<'PYTHON'
import json, sys

def deep_merge(base, overlay):
    """Return base with missing keys filled in from overlay."""
    result = dict(base)
    for key, val in overlay.items():
        if key not in result:
            result[key] = val
        elif isinstance(result[key], dict) and isinstance(val, dict):
            result[key] = deep_merge(result[key], val)
    return result

src_path, tgt_path, direction, claude_dir = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(src_path) as f:
    src_content = f.read()
with open(tgt_path) as f:
    tgt_content = f.read()

# Transform source paths based on direction
if direction == 'from':
    # Parameterize: replace absolute paths with $CLAUDE_HOME
    src_content = src_content.replace(claude_dir, '$CLAUDE_HOME')
else:
    # Expand: replace $CLAUDE_HOME with absolute paths
    src_content = src_content.replace('$CLAUDE_HOME', claude_dir)

source = json.loads(src_content)
target = json.loads(tgt_content)

merged = deep_merge(target, source)

with open(tgt_path, 'w') as f:
    json.dump(merged, f, indent=2)
    f.write('\n')
PYTHON
    echo "  ✓ $name (merged)"
}

# ---------------------------------------------------------------------------
# Main sync loop
# ---------------------------------------------------------------------------
mkdir -p "$TGT"

echo "dotAI sync: $DIRECTION --$STRATEGY"
echo "  source: $SRC"
echo "  target: $TGT"
echo ""

# --- Directories ---
for item in "${MANAGED_DIRS[@]}"; do
    if [ "$STRATEGY" = "overwrite" ]; then
        sync_directory_overwrite "$SRC/$item" "$TGT/$item" "$item"
    else
        sync_directory_merge "$SRC/$item" "$TGT/$item"
    fi
done

# --- Files ---
for item in "${MANAGED_FILES[@]}"; do
    src_path="$SRC/$item"
    tgt_path="$TGT/$item"

    if [ "$STRATEGY" = "overwrite" ]; then
        if [ ! -f "$src_path" ]; then
            echo "  ⊘ $item — source missing, skipped"
            continue
        fi

        if is_legacy_symlink "$tgt_path"; then
            rm -f "$tgt_path"
            echo "  ↳ removed legacy symlink"
        elif [ -e "$tgt_path" ] || [ -L "$tgt_path" ]; then
            backup_target "$tgt_path" "$item"
        fi

        cp "$src_path" "$tgt_path"
        echo "  ✓ $item"
    else
        merge_json "$src_path" "$tgt_path"
    fi
done

# ---------------------------------------------------------------------------
# Plugin state sync
# ---------------------------------------------------------------------------
PLUGIN_SRC="$SRC/plugins"
PLUGIN_TGT="$TGT/plugins"
mkdir -p "$PLUGIN_TGT"

echo ""
echo "Plugin state:"

# --- Plugin state files (with path transformation) ---
for item in "${PLUGIN_STATE_FILES[@]}"; do
    src_path="$PLUGIN_SRC/$item"
    tgt_path="$PLUGIN_TGT/$item"

    if [ "$STRATEGY" = "overwrite" ]; then
        if [ ! -f "$src_path" ]; then
            echo "  ⊘ $item — source missing, skipped"
            continue
        fi

        if is_legacy_symlink "$tgt_path"; then
            rm -f "$tgt_path"
            echo "  ↳ removed legacy symlink"
        elif [ -e "$tgt_path" ] || [ -L "$tgt_path" ]; then
            backup_target "$tgt_path" "plugins/$item"
        fi

        # Transform paths based on sync direction
        if [ "$DIRECTION" = "from" ]; then
            # from ~/.claude to repo: parameterize paths
            parameterize_plugin_paths "$src_path" "$tgt_path" "$CLAUDE_DIR"
        else
            # to ~/.claude from repo: expand paths
            expand_plugin_paths "$src_path" "$tgt_path" "$CLAUDE_DIR"
        fi
    else
        # Merge mode: use merge_plugin_json with path transformation
        merge_plugin_json "$src_path" "$tgt_path" "$DIRECTION" "$CLAUDE_DIR"
    fi
done

# ---------------------------------------------------------------------------
# Plugin whitelist prompt (sync-to only)
# ---------------------------------------------------------------------------
if [ "$DIRECTION" = "to" ]; then
    WHITELIST="$REPO_DIR/plugins/whitelist.json"
    if [ -f "$WHITELIST" ]; then
        plugins=$(grep -o '"[^"]*"' "$WHITELIST" | tr -d '"' | sed '/^$/d') || true
        if [ -n "$plugins" ]; then
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Plugin setup — run these commands inside Claude Code:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            while IFS= read -r plugin; do
                echo "  /plugin install $plugin"
            done <<< "$plugins"
            echo ""
        fi
    fi

    # Marketplace update prompt
    KNOWN_MARKETPLACES="$REPO_DIR/plugins/known_marketplaces.json"
    if [ -f "$KNOWN_MARKETPLACES" ]; then
        # Check if file has any marketplace entries (not empty object)
        has_marketplaces=$(python3 -c "import json; print(len(json.load(open('$KNOWN_MARKETPLACES'))) > 0)" 2>/dev/null) || true
        if [ "$has_marketplaces" = "True" ]; then
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "Marketplace setup — run this command inside Claude Code:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  /plugin marketplace update"
            echo ""
        fi
    fi
fi

echo "Done."
