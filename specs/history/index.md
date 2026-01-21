# Spec History

This directory contains the implementation history for completed development specs. Each history document records what was built, files changed, and design decisions made.

## Purpose

- Provide a record of implemented features and their scope
- Document files changed for each development phase
- Track design decisions (see `docs/design.md`)
- Enable future developers to understand the evolution of the codebase

## Structure

Each spec history file follows this format:

```markdown
# [Spec Name]

## Overview
Brief description of the spec's scope and goals

## Implementation Summary
High-level summary of what was built

## Files Changed
Categorised list of added/modified files

## Features Implemented
Bulleted list of completed features

## Documentation Updates
Links to any docs created or updated
```

## Adding New History Entries

When completing a spec:

1. Create `specs/history/[branch-name].md`
2. Use the spec's tasks.md as the source of completed work
3. Extract file changes from git: `git diff --stat main...[branch]`
4. Register design decisions in `docs/design.md`
5. Move the original spec directory to archive if desired

## History Index

| Spec | Branch | Status | Description |
|------|--------|--------|-------------|
| [Core Features](core-features.md) | dev-0 | Complete | UI, AI validation, local estimation, modelling, component system |
| [WebAuthn Authentication](webauthn-authentication.md) | dev-1 | Complete | Server-side WebAuthn with YubiKey support |
