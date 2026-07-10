#!/usr/bin/env bash
# Create an in-repo git worktree under .worktrees/<name> and copy nextup.md in.
# Usage:
#   tools/new_worktree.sh <name> [branch]
#     <name>    directory created under .worktrees/, and the default branch name
#     [branch]  branch to check out; created off the current HEAD if it does not
#               already exist. Defaults to <name>.
#
# Examples:
#   tools/new_worktree.sh home-router ui/home-router
#   tools/new_worktree.sh model-foundation estimation/model-foundation
set -euo pipefail

name="${1:?usage: new_worktree.sh <name> [branch]}"
branch="${2:-$name}"

# Resolve the main checkout root (the worktree whose .git is a real directory).
# --git-common-dir is ".git" from the main checkout and an absolute path from a
# linked worktree; its parent is the main checkout root either way.
common_dir="$(git rev-parse --git-common-dir)"
main_root="$(cd "$(dirname "$common_dir")" && pwd)"
wt_dir="$main_root/.worktrees/$name"

if [ -e "$wt_dir" ]; then
    echo "error: $wt_dir already exists" >&2
    exit 1
fi

if git -C "$main_root" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$main_root" worktree add "$wt_dir" "$branch"
else
    git -C "$main_root" worktree add -b "$branch" "$wt_dir"
fi

# Copy nextup.md.
if [ -e "$main_root/nextup.md" ]; then
    cp "$main_root/nextup.md" "$wt_dir/nextup.md"
    echo "copied nextup.md from $main_root/nextup.md"
else
    echo "note: no nextup.md in the main checkout to seed"
fi

echo "worktree ready: $wt_dir  [$branch]"
