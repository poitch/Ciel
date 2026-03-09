---
name: review
description: Review uncommitted changes for code style, bugs, and security issues.
disable-model-invocation: true
argument-hint: "[file path or glob, optional - reviews all changes by default]"
allowed-tools: Bash(git *), Read, Glob, Grep
---

# Review Changes

Review your own uncommitted changes for code style, bugs, and security issues.

## Step 1: Gather the diff

If the user provided a path or glob as `$ARGUMENTS`, scope the diff to those files. Otherwise review all changes.

Run these in parallel:

```
git diff -- $ARGUMENTS
git diff --cached -- $ARGUMENTS
git diff --name-only -- $ARGUMENTS
```

If there is no diff (no staged or unstaged changes), inform the user there is nothing to review and stop.

## Step 2: Read full context for every changed file

For each file listed in the diff, use the Read tool to read the **entire file** (not just the diff hunks). You need the surrounding code to catch issues that depend on context — e.g. unused imports, mismatched function signatures, missing error handling in callers.

Read all changed files in parallel.

## Step 3: Review for issues

Carefully analyze the diff **and** the full file context. Check for the following categories:

### Code style
- Naming conventions inconsistent with the rest of the file or project
- Missing type annotations on new function parameters or return types (project convention)
- Obvious formatting issues (e.g. inconsistent indentation, trailing whitespace)
- Dead code: unused imports, unreachable branches, variables assigned but never read

### Bugs
- Off-by-one errors, wrong variable names, copy-paste mistakes
- Missing `await` on async calls
- Incorrect function signatures or argument order
- State mutations that could cause race conditions
- Null/undefined access without guards
- Logic errors: inverted conditions, wrong operator, swapped branches

### Security
- OWASP Top 10: injection (SQL, command, XSS), broken auth, sensitive data exposure
- Secrets or credentials hardcoded or logged
- User input used without validation or sanitization
- Missing CSRF protection, improper CORS configuration
- Insecure use of cryptographic functions
- Path traversal or file access vulnerabilities

## Step 4: Report findings

Present findings grouped by category. For each issue:
- Reference the file and line number (`path/to/file.py:42`)
- Quote the problematic code
- Explain what the issue is and why it matters
- Suggest a fix

If there are no issues, say so clearly — don't invent problems.

Use severity labels:
- **critical** — Must fix before merging (security vulnerabilities, data loss, crashes)
- **warning** — Should fix (bugs, logic errors, missing error handling)
- **nit** — Optional improvement (style, naming, minor readability)
