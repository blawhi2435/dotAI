# Coding Standards and Best Practices

This document provides coding standards and best practices for AI-assisted development. Follow these guidelines when writing, reviewing, or refactoring code.

## Core Development Principles

### 1. Follow Project Architecture
Unless explicitly requested otherwise, all code changes should align with the existing project structure and architectural patterns.

### 2. Test-Driven Development (TDD)
Write tests first, then implementation. This is non-negotiable.

**Testing Requirements:**
- Unit tests must mock external dependencies:
  - Database connections
  - Redis/cache services
  - External API calls
  - Cross-layer dependencies (in clean architecture)
- Tests should be isolated and fast
- Each component should be testable independently

## Code Quality Principles

### 1. Readability First
**Code is read more than it is written.**

Guidelines:
- Use clear, descriptive variable and function names
- Prefer self-documenting code over comments
- Maintain consistent formatting throughout the codebase
- Follow language-specific naming conventions (e.g., camelCase, PascalCase, snake_case)

### 2. KISS (Keep It Simple, Stupid)
**Choose the simplest solution that works.**

Guidelines:
- Avoid over-engineering
- No premature optimization
- Prioritize code that is easy to understand over "clever" code
- If you can't explain it simply, it's probably too complex

### 3. DRY (Don't Repeat Yourself)
**Every piece of knowledge should have a single, authoritative representation.**

Guidelines:
- Extract common logic into reusable functions
- Create shared utilities and components
- Avoid copy-paste programming
- If you find yourself writing similar code twice, refactor

### 4. YAGNI (You Aren't Gonna Need It)
**Don't build features before they're actually needed.**

Guidelines:
- Avoid speculative generality
- Add complexity only when requirements demand it
- Start with simple implementations
- Refactor to add flexibility when needed, not before

## Code Smell Detection

Watch for these anti-patterns and refactor when detected:

### 1. Long Functions
Functions should rarely exceed 50 lines. If they do, break them into smaller, focused functions.

```go
// ❌ BAD: Function > 50 lines
func ProcessMarketData(data []byte) error {
    // 100+ lines of validation, transformation, and storage
    // ...
    return nil
}

// ✅ GOOD: Split into smaller, focused functions
func ProcessMarketData(data []byte) error {
    validated, err := validateData(data)
    if err != nil {
        return err
    }

    transformed := transformData(validated)
    return saveData(transformed)
}
```

### 2. Deep Nesting
Avoid nesting beyond 3-4 levels. Use early returns and guard clauses.

```go
// ❌ BAD: 5+ levels of nesting
func ProcessRequest(user *User, market *Market) error {
    if user != nil {
        if user.IsAdmin {
            if market != nil {
                if market.IsActive {
                    if hasPermission(user, market) {
                        // Do something
                        return nil
                    }
                }
            }
        }
    }
    return errors.New("invalid request")
}

// ✅ GOOD: Early returns with guard clauses
func ProcessRequest(user *User, market *Market) error {
    if user == nil {
        return errors.New("user is nil")
    }
    if !user.IsAdmin {
        return errors.New("user is not admin")
    }
    if market == nil {
        return errors.New("market is nil")
    }
    if !market.IsActive {
        return errors.New("market is not active")
    }
    if !hasPermission(user, market) {
        return errors.New("permission denied")
    }

    // Do something
    return nil
}
```

### 3. Magic Numbers
Never use unexplained numeric literals. Always use named constants.

```go
// ❌ BAD: Unexplained numbers
func RetryOperation() {
    if retryCount > 3 {
        return
    }
    time.Sleep(500 * time.Millisecond)
}

// ✅ GOOD: Named constants with clear intent
const (
    MaxRetries      = 3
    RetryDelayMs    = 500
)

func RetryOperation() {
    if retryCount > MaxRetries {
        return
    }
    time.Sleep(RetryDelayMs * time.Millisecond)
}
```

## Summary

**Remember: Code quality is not negotiable.**

Clear, maintainable code enables:
- Rapid development
- Confident refactoring
- Easier debugging
- Better collaboration
- Reduced technical debt

### When in Doubt

1. **Simplicity wins** - Choose the clearer solution
2. **Ask questions** - Clarify requirements before coding
3. **Refactor fearlessly** - Tests give you confidence
4. **Review ruthlessly** - Question every line's necessity

---

*These principles apply to all programming languages and paradigms. Adapt examples to your specific language and framework while maintaining the core concepts.*
