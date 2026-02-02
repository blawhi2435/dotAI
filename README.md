# dotAI

Bidirectional sync tool for Claude Code configuration. Keep your `~/.claude` settings, skills, hooks, and commands version-controlled and portable across machines.

## What it syncs

| Item | Description |
|------|-------------|
| `skills/` | Custom skills for Claude Code |
| `commands/` | Custom slash commands |
| `hooks/` | Event hooks |
| `rules/` | Custom rules |
| `settings.json` | Claude Code settings (enabled plugins, preferences) |
| `plugins/*.json` | Plugin state (installed plugins, marketplace registrations) |

## Usage

```bash
# Pull config from repo to ~/.claude (replaces existing)
./sync.sh to --overwrite

# Pull config, keeping existing files (adds missing only)
./sync.sh to --merge

# Push ~/.claude config to repo (replaces existing)
./sync.sh from --overwrite

# Push config, keeping existing repo files (adds missing only)
./sync.sh from --merge
```

## Sync strategies

**`--overwrite`**: Backs up the target to `.bak`, then replaces it entirely with source content.

**`--merge`**: Adds missing files/keys from source without modifying existing content. JSON files are deep-merged.

## Setup

1. Clone this repo
2. Run `./sync.sh to --merge` to apply the config
3. Follow any plugin setup prompts that appear

After syncing to `~/.claude`, you may need to run plugin commands inside Claude Code:
- `/plugin marketplace update` — refresh marketplace plugins
- `/plugin install <name>` — install specific plugins

## Workflow

**New machine setup:**
```bash
git clone <this-repo> ~/dotAI
cd ~/dotAI
./sync.sh to --overwrite
```

**Save local changes:**
```bash
./sync.sh from --overwrite
git add -A && git commit -m "update config"
git push
```

**Pull updates:**
```bash
git pull
./sync.sh to --merge  # or --overwrite to fully replace
```

## Directory structure

```
dotAI/
├── skills/              # Custom skills
├── commands/            # Custom slash commands
├── hooks/               # Event hooks
├── rules/               # Custom rules
├── plugins/
│   ├── installed_plugins.json
│   └── known_marketplaces.json
├── settings.json        # Claude Code settings
└── sync.sh              # Sync script
```

## Notes

- Backups are created as `*.bak` before overwriting
- Legacy symlinks (from older setup methods) are automatically cleaned up
- Plugin cache and marketplace directories are gitignored — they're regenerated locally
