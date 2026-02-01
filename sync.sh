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

# ---------------------------------------------------------------------------
# Managed items
# ---------------------------------------------------------------------------
MANAGED_DIRS=("skills" "commands" "hooks" "rules")
MANAGED_FILES=("settings.json")
PLUGIN_STATE_DIRS=("cache" "marketplaces")
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

# backup_target <path>
# Moves <path> to <path>.bak. Overwrites previous .bak if present.
backup_target() {
    local tgt="$1"
    local bak="${tgt}.bak"
    if [ -e "$bak" ] || [ -L "$bak" ]; then
        rm -rf "$bak"
    fi
    mv "$tgt" "$bak"
    echo "  ↳ backed up to $(basename "$bak")"
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

# sync_directory_overwrite <src> <tgt>
# Backs up tgt, then makes tgt an exact copy of src.
sync_directory_overwrite() {
    local src="$1" tgt="$2" name
    name="$(basename "$tgt")"

    if [ ! -d "$src" ]; then
        echo "  ⊘ $name — source missing, skipped"
        return
    fi

    if is_legacy_symlink "$tgt"; then
        rm -f "$tgt"
        echo "  ↳ removed legacy symlink"
    elif [ -e "$tgt" ] || [ -L "$tgt" ]; then
        backup_target "$tgt"
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
        sync_directory_overwrite "$SRC/$item" "$TGT/$item"
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
            backup_target "$tgt_path"
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

# --- Plugin state directories ---
for item in "${PLUGIN_STATE_DIRS[@]}"; do
    if [ "$STRATEGY" = "overwrite" ]; then
        sync_directory_overwrite "$PLUGIN_SRC/$item" "$PLUGIN_TGT/$item"
    else
        sync_directory_merge "$PLUGIN_SRC/$item" "$PLUGIN_TGT/$item"
    fi
done

# --- Plugin state files ---
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
            backup_target "$tgt_path"
        fi

        cp "$src_path" "$tgt_path"
        echo "  ✓ $item"
    else
        merge_json "$src_path" "$tgt_path"
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
fi

echo "Done."
