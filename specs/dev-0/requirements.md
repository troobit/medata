## Merge Worktrees

Merge the following worktrees into `dev-0`:

1. **auth** (`/Users/ronan/repos/beetus/auth`) - Authentication changes. Priority: HIGH.
2. **datagen** (`/Users/ronan/repos/beetus/datagen`) - Data generation changes.

Prioritise non-conflicting changes first. Where conflicts exist, resolve them sensibly.

## Documentation

Update documentation to match the current setup after merges are complete.

## Spelling

Enforce Irish/British spelling throughout the codebase. Continuously check for and replace:

- `color` → `colour`
- `realize` → `realise`
- `-ize` endings → `-ise` endings
- Other American spellings as found
