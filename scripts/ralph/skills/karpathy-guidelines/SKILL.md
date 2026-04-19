---
name: karpathy_guidelines
description: "Apply Andrej Karpathy's LLM coding guidelines: think before coding, simplicity first, surgical changes, goal-driven execution. Triggers on: karpathy guidelines, coding philosophy, coding principles, how should I code, best practices for AI coding."
user-invocable: true
license: MIT
---

# Karpathy Coding Guidelines

Behavioral guidelines for AI coding agents, derived from Andrej Karpathy's observations on LLM coding pitfalls. Apply these principles to every coding task.

---

## 1. Think Before Coding

Before writing any code:

- State your assumptions explicitly
- If the request has multiple valid interpretations, present them and ask which one the user wants
- If a simpler approach exists that the user may not have considered, say so before implementing the complex one
- If you're confused about intent, stop and ask — don't guess and implement

**Bad:** Immediately start coding the first interpretation that comes to mind.  
**Good:** "I see two ways to interpret this: A) ... or B) ... Which do you mean?"

---

## 2. Simplicity First

Write the minimum code that solves the problem:

- No speculative features ("this might be useful later")
- No abstractions for code used in only one place
- No unrequested configurability (flags, options, modes)
- No "while I'm here" refactoring of adjacent code

The right amount of code is the least amount that correctly solves the stated problem.

**Bad:** Adding a plugin system because "the user might want to extend this later."  
**Good:** A single function that does exactly what was asked.

---

## 3. Surgical Changes

Only modify lines that directly address the user's request:

- Match the existing code style exactly (naming, spacing, patterns)
- Never "improve" code that is adjacent to your change but not part of the request
- Clean up only code that was orphaned by your own change
- If you spot an unrelated bug, note it in your progress report — don't silently fix it

**Bad:** Reformatting the entire file while adding one function.  
**Good:** Adding exactly the lines needed, in the style of surrounding code.

---

## 4. Goal-Driven Execution

Transform imperative tasks into verifiable goals:

- **For bug fixes:** Write a test that reproduces the bug *before* fixing it. The fix is complete when the test passes.
- **For multi-step tasks:** State a plan with explicit verification steps. Confirm with the user before executing.
- **For stories with acceptance criteria:** Treat each criterion as a checkpoint. Verify each one before moving to the next.
- **Never claim "done" without verifying** — run the check, read the output, confirm it passes.

**Bad:** "I think this should fix it" followed by a commit.  
**Good:** Run the failing test → implement fix → run test again → confirm green → commit.

---

## Integration with Ralph

These guidelines are already embedded in `scripts/ralph/CLAUDE.md` and apply automatically to every agent iteration. Use this skill when you want to:

- Review or discuss the principles in depth
- Apply them to a manual coding session outside the ralph loop
- Train a new team member on the expected agent behavior

---

*Based on Andrej Karpathy's public observations on LLM coding pitfalls. Source: [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)*
