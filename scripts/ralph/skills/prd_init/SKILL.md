---
name: prd_init
description: "Initialize a new project by creating a PRD and converting it directly to prd.json. Use when starting a new project or feature from scratch. Triggers on: nowy projekt, new project, create prd, prd init, zaplanuj projekt, zacznijmy projekt, chcę zbudować, want to build, plan this, start project."
user-invocable: true
---

# PRD Init

Create a complete Product Requirements Document and convert it directly to `prd.json` — no intermediate files.

---

## The Job

1. Receive a feature or project idea from the user
2. Ask up to 10 clarifying questions (with lettered options)
3. Generate structured stories and show them for user review
4. Incorporate feedback and adjustments
5. Write `prd.json` directly — skip the markdown step

**Do NOT start implementing. Do NOT create a .md file unless the user explicitly asks for one.**

---

## Step 1: Clarifying Questions

Ask all questions that are genuinely ambiguous or critical. Do not skip questions just to be fast — thorough questions produce better stories. Ask up to 10, covering:

- **Problem/Goal:** What problem does this solve? What's the pain point?
- **Target Users:** Who uses this? New users, existing users, admins?
- **Core Actions:** What are the 3-5 key things a user must be able to do?
- **Scope Boundaries:** What should it explicitly NOT do? (Prevents scope creep)
- **Tech Stack:** Framework, language, database? (Or ask if unknown)
- **Authentication:** Is login/auth required? Existing system or new?
- **Data Persistence:** What data must be stored? How long?
- **Integrations:** External APIs, services, third-party tools needed?
- **Success Definition:** How will we know it's working? What metrics matter?
- **MVP vs Full:** Is this a minimal first version or a full feature?

### Question Format

```
1. What is the primary problem this solves?
   A. [Option]
   B. [Option]
   C. [Option]
   D. Other: [please specify]

2. Who are the target users?
   A. End users (consumers)
   B. Internal team / admins
   C. Both
   D. Developers / API consumers

3. What tech stack will this use?
   A. Next.js + PostgreSQL
   B. Next.js + SQLite
   C. Pure React + REST API
   D. Other: [please specify]
```

Users can respond with `"1A, 2C, 3B"` for quick answers. Skip questions where the answer is obvious from context. Ask follow-ups if an answer opens new ambiguities.

---

## Step 2: Generate Stories and Show for Review

Before writing any files, present the proposed stories:

```
Here are the stories I'll create:

US-001: [Title] — [one-line summary]
US-002: [Title] — [one-line summary]
...

Does this look right? You can:
- Say "ok" to proceed
- Ask me to add/remove/split a story
- Clarify any acceptance criteria
```

Incorporate all feedback before writing.

---

## Step 3: Write prd.json

Write directly to `scripts/ralph/prd.json` (or `prd.json` in root if configured):

```json
{
  "project": "[Project Name]",
  "branchName": "ralph/[feature-name-kebab-case]",
  "description": "[Feature description]",
  "stories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Specific verifiable criterion",
        "Another criterion",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

---

## Story Rules (Critical)

### Size: One Context Window Per Story

Each story must be completable in ONE ralph iteration. A fresh agent with no memory implements it start-to-finish.

**Right-sized:**
- Add a database column and migration
- Add a UI component to an existing page
- Add a filter dropdown to a list
- Create a single API endpoint

**Too big — split these:**
- "Build the entire dashboard" → schema, queries, components, filters (4+ stories)
- "Add authentication" → schema, middleware, login UI, session handling (4 stories)
- "Refactor the API" → one story per endpoint

Rule of thumb: if you cannot describe the change in 2-3 sentences, split it.

### Ordering: Dependencies First

```
1. Schema / database migrations
2. Server actions / backend logic
3. UI components using the backend
4. Dashboard / aggregate views
```

Never have a story depend on a later story.

### Acceptance Criteria: Verifiable Only

| Good | Bad |
|------|-----|
| "Add `status` column: 'pending'\|'active'\|'done'" | "Works correctly" |
| "Filter dropdown shows: All, Active, Done" | "Good UX" |
| "Clicking delete shows confirmation dialog" | "Handles edge cases" |

**Always include as final criterion:**
- `"Typecheck passes"` — every story
- `"Tests pass"` — stories with testable logic
- `"Verify in browser using playwright-skill"` — every UI story
- `"A failing test reproducing the bug exists before the fix"` — every bug fix story

### Archiving Previous Runs

Before writing prd.json, check if one already exists:
1. Read current `prd.json` if it exists
2. If `branchName` differs from the new feature: archive it
   - Create `archive/YYYY-MM-DD-[old-branchName]/`
   - Copy current `prd.json` and `progress.txt` there
   - Reset `progress.txt` with fresh header

---

## Checklist Before Writing

- [ ] Asked all relevant clarifying questions (up to 10)
- [ ] Showed stories for user review and incorporated feedback
- [ ] Each story is completable in one iteration
- [ ] Stories ordered by dependency (schema → backend → UI)
- [ ] Every story has "Typecheck passes"
- [ ] UI stories have "Verify in browser" criterion
- [ ] Bug stories have test-first criterion
- [ ] Archived previous prd.json if branchName differs
- [ ] Wrote to `scripts/ralph/prd.json`
