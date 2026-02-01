---
name: git-commit
description: Generate and execute git commits with Conventional Commits format. Use when the user wants to commit changes, create commits, or asks to commit staged/unstaged work. Analyzes changes, suggests splitting into logical commits, and requires user confirmation before each commit.
---

# Git Commit

Generate commit messages following Conventional Commits and execute commits with user confirmation.

## Workflow

1. Run `git status` and `git diff` to view all changes
2. Analyze changes and determine if they should be split into multiple commits (by feature, type, or scope)
3. For each commit, generate a message and ask for confirmation before executing
4. After each commit, display remaining commit count

## Commit Message Format

```
type(scope): description
```

### Types

| Type | Use for |
|------|---------|
| feat | Add, adjust, or remove a feature (API or UI) |
| fix | Fix a bug from a previous feat commit |
| refactor | Rewrite/restructure code without changing behavior |
| perf | Performance improvements (special refactor) |
| style | Code style only (whitespace, formatting, semicolons) |
| test | Add or correct tests |
| docs | Documentation only |
| build | Build tools, dependencies, project version |
| ops | Infrastructure, deployment, CI/CD, monitoring |
| chore | Misc tasks (initial commit, .gitignore, etc.) |

### Description Guidelines

- Clearly explain "what was done" and "why"
- Use imperative mood ("add feature" not "added feature")
- Keep under 72 characters
- No period at the end

## Confirmation Flow

For each proposed commit:

1. Show the commit message
2. Show which files will be included
3. Wait for user confirmation (yes/no/edit)
4. If confirmed, execute `git add <files> && git commit -m "message"`
5. Display: "✓ Committed. Remaining commits: N"

## Important Rules

- Never commit without user confirmation
- Never add auto-generated footers (no "Co-Authored-By", no "Generated with...")
- Never use `git add -A` or `git add .` — always add specific files
- If user says "no", skip that commit and continue to next
- If user wants to edit, accept their revised message
