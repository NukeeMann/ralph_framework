---
name: prd_append
description: "Add bugs and new features to an existing prd.json mid-project. Use when you have a rough list of issues, bugs, or feature requests discovered during development. Triggers on: mam bugi, found bugs, dodaj taski, append tasks, new features to add, lista bugów, lista tasków, mid-project tasks, triage bugs."
user-invocable: true
---

# PRD Append

Take a rough list of bugs and/or new features discovered mid-project and append them as properly formatted stories to the existing `prd.json`.

---

## The Job

1. Read existing `prd.json` to understand current state
2. Receive the user's rough list (pasted text, file path, or typed inline)
3. Classify each item: bug, feature, or enhancement
4. Ask clarifying questions for any item that is ambiguous or underspecified
5. Show proposed new stories for review
6. Append approved stories to `prd.json` — never touch existing stories

**Never modify, remove, or reorder existing stories. Never change `passes: true` entries.**

---

## Step 1: Read Existing prd.json

Before anything else, read `scripts/ralph/prd.json` to understand:
- Current project name and branchName
- Highest existing priority number
- Which stories are done (`passes: true`) vs pending (`passes: false`)
- The naming conventions used (IDs, titles)

New stories continue from the highest existing ID and priority:
- If last story is `US-007` with priority 7, new stories start at `US-008` with priority 8+.

---

## Step 2: Classify Each Item

For each item in the user's list, determine:

| Type | Signals | Treatment |
|------|---------|-----------|
| **Bug** | "nie działa", "błąd", "crashes", "wrong", "broken", "fix" | Test-first criterion mandatory |
| **Feature** | "dodaj", "chcę", "potrzebuję", "add", "implement", "new" | Standard story format |
| **Enhancement** | "popraw", "ulepsz", "improve", "better", "refactor" | Standard story format, note scope carefully |

---

## Step 3: Ask Clarifying Questions

For each item that is unclear, ask targeted questions **before** formatting it into a story. Do not guess.

### When to ask:
- Bug with no reproduction steps → ask how to reproduce it
- Feature with no acceptance definition → ask what "done" looks like
- Ambiguous scope → ask what's in/out
- Unknown priority → ask if it blocks anything else

### Question format (per item):

```
Item 3: "login czasem nie działa"
  A. Does it always fail or only sometimes? What triggers it?
  B. What error do users see (if any)?
  C. Which login method — email/password, OAuth, or both?
```

Wait for answers before proceeding. It's fine to batch questions for multiple items in one message.

---

## Step 4: Format Stories

### Bug Story Format

```json
{
  "id": "US-008",
  "title": "Fix: [short description of the bug]",
  "description": "As a [user], when [condition], [broken behavior] occurs instead of [expected behavior].",
  "acceptanceCriteria": [
    "A failing test reproducing the bug exists before the fix",
    "[Specific verifiable fix criterion]",
    "[Another criterion if needed]",
    "Typecheck passes",
    "Tests pass"
  ],
  "priority": 8,
  "passes": false,
  "notes": "Reproduction: [how to trigger the bug]"
}
```

### Feature / Enhancement Story Format

```json
{
  "id": "US-009",
  "title": "[Action verb]: [what it does]",
  "description": "As a [user], I want [feature] so that [benefit].",
  "acceptanceCriteria": [
    "Specific verifiable criterion",
    "Another criterion",
    "Typecheck passes"
  ],
  "priority": 9,
  "passes": false,
  "notes": ""
}
```

---

## Step 5: Show for Review

Before appending, present proposed stories:

```
Here are the stories I'll add:

US-008 [BUG]: Login fails on mobile Safari — priority 8
US-009 [FEAT]: Export tasks to CSV — priority 9
US-010 [FEAT]: Dark mode toggle — priority 10

Does this look right? You can:
- Say "ok" to append all
- Change priority of any story
- Ask me to split or merge stories
- Drop any item from the list
```

---

## Step 6: Append to prd.json

Append ONLY the approved new stories to the `"stories"` array. Do not rewrite the file — add to the end of the existing array.

---

## Story Size Rule (Same as prd_init)

Each story must be completable in ONE ralph iteration (one context window).

If a bug or feature is too large, split it:
- Bug with multiple root causes → one story per cause
- Feature spanning schema + backend + UI → minimum 3 stories

---

## Acceptance Criteria Rules

**Bug stories — always include as first criterion:**
```
"A failing test reproducing the bug exists before the fix"
```

**All stories — always include:**
```
"Typecheck passes"
```

**Stories with logic — include:**
```
"Tests pass"
```

**UI stories — include:**
```
"Verify in browser using playwright-skill"
```

---

## Priority Assignment

Assign priorities that reflect real urgency:
- Bugs that block other stories → lower number (higher priority) than those stories
- Bugs that don't block → after current pending stories
- New features → after all current pending stories, unless user specifies otherwise

Ask the user if priority is unclear: *"Does this bug block any current stories, or can it wait?"*

---

## Checklist Before Appending

- [ ] Read existing prd.json to know current state
- [ ] Classified each item (bug / feature / enhancement)
- [ ] Asked clarifying questions for ambiguous items
- [ ] Bug stories have test-first criterion
- [ ] UI stories have browser verification criterion
- [ ] All stories have "Typecheck passes"
- [ ] Each story is small enough for one iteration (split if not)
- [ ] Priorities assigned relative to existing stories
- [ ] Showed proposed stories to user and got approval
- [ ] Appended ONLY — did not modify existing stories
