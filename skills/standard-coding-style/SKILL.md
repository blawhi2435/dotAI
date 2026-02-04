---
name: standard-coding-style
description: Enforce coding standards and best practices during AI-assisted development. Use when writing new code, reviewing existing code, refactoring code, or implementing features. Ensures adherence to TDD, KISS, DRY, YAGNI principles, and detects common code smells like long functions, deep nesting, and magic numbers. Apply to all programming tasks involving code creation or modification.
---

# Standard Coding Style

Enforce coding standards and best practices for AI-assisted development.

## Quick Reference

**Core Principles:**
1. **TDD** - Write tests first, then implementation
2. **KISS** - Keep it simple
3. **DRY** - Don't repeat yourself
4. **YAGNI** - You aren't gonna need it
5. **Readability First** - Code is read more than written

**Code Smells to Avoid:**
- Functions > 50 lines
- Nesting > 3-4 levels
- Magic numbers without constants

## Workflow

When writing, reviewing, or refactoring code:

### 1. Before Writing Code

**Read the detailed standards:**
```
references/coding-standards.md
```

**Key checks:**
- ✅ Tests written first (TDD)
- ✅ External dependencies mocked
- ✅ Following existing architecture
- ✅ Clear, descriptive naming
- ✅ Simplest solution chosen

### 2. During Implementation

**Apply principles actively:**
- Extract repeated code → DRY
- Split long functions (>50 lines) → smaller functions
- Use early returns → avoid deep nesting
- Name constants → no magic numbers
- Question complexity → KISS

### 3. After Writing Code

**Self-review checklist:**
- [ ] Tests pass and cover key paths
- [ ] Functions < 50 lines
- [ ] Nesting < 4 levels
- [ ] No magic numbers
- [ ] No repeated logic
- [ ] Clear variable/function names
- [ ] No premature optimization

## Common Patterns

### ✅ Good: Early Returns

```go
func ProcessRequest(user *User) error {
    if user == nil {
        return errors.New("user is nil")
    }
    if !user.IsAdmin {
        return errors.New("not admin")
    }
    // Process
    return nil
}
```

### ❌ Bad: Deep Nesting

```go
func ProcessRequest(user *User) error {
    if user != nil {
        if user.IsAdmin {
            // Process
            return nil
        }
    }
    return errors.New("invalid")
}
```

### ✅ Good: Named Constants

```go
const MaxRetries = 3

func Retry() {
    if count > MaxRetries {
        return
    }
}
```

### ❌ Bad: Magic Numbers

```go
func Retry() {
    if count > 3 {  // What does 3 mean?
        return
    }
}
```

## Detailed Standards

For complete guidelines including:
- TDD testing requirements
- Code quality principles (KISS, DRY, YAGNI, Readability)
- Code smell detection patterns
- Language-specific examples

Read: `references/coding-standards.md`

## When in Doubt

1. **Simplicity wins** - Choose the clearer solution
2. **Ask questions** - Clarify requirements before coding
3. **Refactor fearlessly** - Tests give you confidence
4. **Review ruthlessly** - Question every line's necessity
