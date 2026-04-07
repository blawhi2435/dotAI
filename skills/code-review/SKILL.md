---
name: code-review
description: Use when reviewing any code changes — commits, SHA ranges, or uncommitted working tree changes — whether AI-generated or human-written.
---

# Code Review

Dispatch parallel specialist subagents to review code changes. Each specialist reads the diff and relevant codebase context to infer project conventions — no config needed.

**NEVER review code in a single pass in the main conversation. ALWAYS dispatch specialist subagents — even for small diffs.**

## Invocation

```bash
/code-review                         # Review working tree (uncommitted changes)
/code-review HEAD~1                  # Review last commit
/code-review <base_sha> <head_sha>   # Review a SHA range
```

Programmatic: called from other skills via `$ARGUMENTS` with `base_sha head_sha`.

## Process

### Step 1: Parse input & get diff

```bash
# Parse $ARGUMENTS
# If two args:  BASE=$1, HEAD=$2
# If one arg:   BASE=$1, HEAD=HEAD
# If empty:     use working tree (git diff)

git diff --stat $BASE..$HEAD   # or git diff --stat for working tree
git diff $BASE..$HEAD          # full diff to pass to specialists
```

### Step 2: Decide which specialists to run

Analyze the diff stat output:

| Specialist | Run when |
|---|---|
| `logic-reviewer` | Always — no exceptions |
| `security-reviewer` | Changed files include: auth, middleware, config, credentials, permissions — OR — diff contains: SQL queries (raw sql.Exec/db.Raw), authentication logic, secret/token handling |
| `test-reviewer` | Changed files include `.test.`, `_test.`, `spec.`, OR logic changes > 50 lines |
| `style-reviewer` | Always — no exceptions |

Tell the user which specialists you are launching before dispatching.

**Red flags — never do these:**
- "The diff is small, I'll review inline" → Always dispatch subagents
- "I'll combine logic and style into one subagent" → Each specialist runs separately
- "Security reviewer isn't needed" → Follow the trigger table strictly
- "This is a docs-only change, no need for full review" → Docs changes still run logic + style specialists
- "I already scanned it, looks fine" → Must dispatch specialists — no inline scanning
- "The file isn't named 'auth' so security review isn't needed" → Check diff content for SQL/token/auth patterns, not just filenames

### Step 3: Dispatch specialists in parallel

Spawn selected specialists simultaneously using the Agent tool.

Pass to EACH specialist:
- Full diff text
- Changed file list (from `git diff --stat`)
- One-line context: what was changed and in what language/framework

Read each prompt file at dispatch time:
- `~/.claude/skills/code-review/logic-reviewer-prompt.md`
- `~/.claude/skills/code-review/security-reviewer-prompt.md`
- `~/.claude/skills/code-review/test-reviewer-prompt.md`
- `~/.claude/skills/code-review/style-reviewer-prompt.md`

### Step 4: Aggregate results

After all specialists complete:

1. **Deduplicate**: remove issues raised by multiple specialists about the same line/file
2. **Classify severity**: Critical / Important / Minor
3. **Format unified report** (see Output Format below)
4. **Give verdict**: Ready to merge? Yes / No / With fixes

## Output Format

```
## Code Review

**Specialists run:** logic, style [, security, test]

### Critical (Must Fix)
- `file.go:42` — [issue] — [why it matters] — [how to fix]

### Important (Should Fix)
- `file.go:87` — [issue] — [why it matters]

### Minor (Nice to Have)
- `file.go:12` — [issue]

### Strengths
- [specific thing done well, with file:line reference]

### Verdict
**Ready to merge:** Yes / No / With fixes
**Reason:** [1-2 sentences]
```

## Integration with Other Skills

This skill can be called from:
- `subagent-driven-development` — after each task
- `executing-plans` — after each batch
- Any other skill that completes a work unit
