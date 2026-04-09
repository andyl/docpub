---
description: Generate a detailed implementation plan for a feature spec and save it to _plans/
argument-hint: Filename of Feature Spec
allowed-tools: Read, Write, Glob, Bash
---

Generate a detailed implementation plan for the spec file at `_spec/features/$ARGUMENTS` and write the result to `_plans/$ARGUMENTS`.

## Instructions

**Step 1 — Read the spec**

Read the full contents of `_spec/features/$ARGUMENTS`. If the file does not exist, stop and tell the user.

**Step 2 — Explore the codebase**

Before planning, orient yourself to the existing codebase:

- Use Glob to discover the directory structure and key files
- Read any relevant existing source files, configs, or related modules that the spec touches
- Identify the tech stack, conventions, and patterns already in use
- Note any dependencies, interfaces, or constraints the implementation must respect

**Step 3 — Think in plan mode**

Think carefully and thoroughly — the same way you would when entering `/plan` mode. Do NOT write any code or make any file edits yet. Instead, reason through:

1. **Goal** — Restate the objective from the spec in one or two sentences.
2. **Scope** — What is in scope and explicitly out of scope?
3. **Architecture & design decisions** — What are the key design choices and why?
4. **Implementation steps** — A numbered, ordered list of concrete tasks. Each step should be:
   - Specific enough to act on without further clarification
   - Scoped to a single logical unit of work (file, function, config, test, etc.)
   - Annotated with the files to create or modify
5. **Dependencies & ordering** — Highlight any steps that must happen before others and why.
6. **Edge cases & risks** — What could go wrong? What needs special attention or validation?
7. **Testing strategy** — How should the implementation be verified (unit tests, integration tests, manual checks)?
8. **Open questions** — Anything ambiguous in the spec that should be clarified before or during implementation.

**Step 4 — Write the plan**

Create the directory `_spec/plans/` if it does not already exist.

Write the plan to `_spec/plans/$ARGUMENTS` using this structure:

```
# Implementation Plan: <title from spec>

**Spec:** `_spec/features/$ARGUMENTS`
**Generated:** <today's date>

---

## Goal

<one or two sentence summary>

## Scope

### In scope
- ...

### Out of scope
- ...

## Architecture & Design Decisions

<key design choices with rationale>

## Implementation Steps

1. **<Step title>**
   - Files: `path/to/file.ts`
   - Details: <what to do and why>

2. **<Step title>**
   ...

## Dependencies & Ordering

<any sequencing constraints between steps>

## Edge Cases & Risks

- <risk or edge case>: <mitigation>

## Testing Strategy

<how to verify correctness>

## Open Questions

- [ ] <question>
```

After writing the file, confirm to the user that the plan has been saved to `_plans/$ARGUMENTS` and give a brief summary of the top-level steps.
