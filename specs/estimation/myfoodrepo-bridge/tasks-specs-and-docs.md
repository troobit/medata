---
references:
    - prd.md
---
# MyFoodRepo-273 bridge — Specs and docs

## Floor annotations

- [x] 1. Annotate the three stale app-level floor references <!-- id:vvfzwvs -->
  - specs/estimation/pipeline/tasks.md:36 (app target still says iOS 17), specs/estimation/pipeline/decision_log.md:229 (iOS 17 / iPhone 12-13 Pro floor, not marked superseded), specs/estimation/model-production/prerequisites.md:16 (13 Pro Max as verify device)
  - Each gets a superseded/annotation note pointing at iOS 26.5 and the iPhone 16 Pro floor (segmenter-foundation Decisions 22/26); annotate, do not rewrite history
  - Leave MedataCore-package iOS 17 references alone (docs/references.md, docs/agent-notes/swift-package.md)
  - Context owns ONLY these three files — no decision logs, no docs/agent-notes, no CHANGELOG

- [x] 2. Spell gate green <!-- id:vvfzwvt -->
  - make spell clean on the annotated files
  - Blocked-by: vvfzwvs (Annotate the three stale app-level floor references)
