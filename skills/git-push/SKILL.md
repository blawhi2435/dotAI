---
name: git-push
description: Safe git push workflow with automatic rebase handling and conflict resolution. Use when (1) user explicitly requests to push commits, (2) after completing a git commit to proactively offer push, or (3) when preparing to share local commits to remote. Handles protected branch warnings, automatic rebasing for feature branches, conflict resolution with user approval, and supports auto-approve mode to skip confirmations.
---

# Git Push

Safe git push workflow that handles rebasing, conflicts, and protected branches automatically.

## Workflow

### 1. Initial Setup

Ask user at the start of the workflow:

> "Would you like me to proceed automatically with all operations, or would you prefer to confirm each step? (auto/confirm)"

Store this preference for the entire workflow:
- **auto mode**: Skip all confirmation prompts, execute operations directly
- **confirm mode**: Ask for user approval at each decision point

### 2. Pre-Push Checks

Check the current branch:

```bash
git branch --show-current
```

**If on protected branch** (dev, develop, staging, master, main):

In **confirm mode**: Warn and ask for confirmation:
> "⚠️ You are about to push to `{branch}` (protected branch). Are you sure you want to continue? (yes/no)"

In **auto mode**: Display warning but proceed:
> "⚠️ Pushing to `{branch}` (protected branch)"

If user confirms or in auto mode, skip to step 4 (push).

**If on feature branch**: Continue to step 3.

### 3. Rebase Check (Feature Branches Only)

Fetch latest changes and check if rebase is needed:

```bash
git fetch origin
```

Check if local branch is behind remote:

```bash
git rev-list HEAD..origin/{branch} --count
```

If count > 0, rebase is needed.

**If rebase needed**:

In **confirm mode**: Ask for confirmation:
> "Your branch is behind `origin/{branch}` by {count} commits. Rebase before pushing? (yes/no)"

In **auto mode**: Display info and proceed:
> "Rebasing onto `origin/{branch}` ({count} commits behind)"

Execute rebase:

```bash
git rebase origin/{branch}
```

**If rebase conflicts occur**:

1. List conflicted files:
```bash
git diff --name-only --diff-filter=U
```

2. Show conflict summary:
```bash
git status --short
```

3. Create conflict resolution plan:
   - List each conflicted file
   - For each file, show the conflict markers or describe the conflict type
   - Propose resolution strategy (e.g., "Keep both changes", "Prefer ours", "Prefer theirs", "Manual merge")

4. In **confirm mode**: Present plan and ask:
   > "Conflict resolution plan:
   > - {file1}: {strategy}
   > - {file2}: {strategy}
   >
   > Proceed with resolution? (yes/no)"

5. In **auto mode**: Display plan and proceed:
   > "Resolving conflicts automatically..."

6. Resolve each conflict according to the plan

7. Stage resolved files:
```bash
git add {resolved_files}
```

8. Continue rebase:
```bash
git rebase --continue
```

9. Repeat steps 1-8 until rebase completes (no more conflicts)

**If no rebase needed**: Continue to step 4.

### 4. Push to Remote

Execute push with tracking:

```bash
git push -u origin {branch}
```

If push is rejected (non-fast-forward), inform user:
> "❌ Push rejected. The remote has changes that you don't have locally. Run the workflow again to rebase and retry."

### 5. Execution Summary

After completion, provide a summary:

```
✅ Push completed successfully

Summary:
- Branch: {branch}
- Protected branch warning: {yes/no}
- Rebase performed: {yes/no}
- Conflicts resolved: {count}
- Commits pushed: {count}
- Remote: origin/{branch}
```

If any errors occurred, include them in the summary with suggestions for resolution.

## Usage After Commits

After executing a git commit (using the git-commit skill or manually), proactively ask:

> "Commit created successfully. Would you like to push this commit to remote? (yes/no)"

If yes, execute this workflow starting from step 1.

## Error Handling

**Push rejected (force required)**: Never use `--force` automatically. Instead:
> "❌ Push requires force. This is dangerous on {branch}. Please review the situation manually or use `git push --force-with-lease` if you're certain."

**Rebase aborted**: If rebase fails and user wants to abort:
```bash
git rebase --abort
```

**Detached HEAD or other git state issues**: Inform user and suggest manual intervention:
> "⚠️ Detected unusual git state: {state}. Please resolve manually before pushing."
