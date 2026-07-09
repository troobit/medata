#!/usr/bin/env bash
# Create an in-repo git worktree under .worktrees/<name> and seed the main
# checkout's nextup.md into it as an independent COPY.
#
# nextup.md is gitignored (see .gitignore), so it does NOT travel into a linked
# worktree on its own — a fresh worktree would have no nextup.md at all. This
# script copies it in so the worktree starts from the same nextup.md as root.
#
# It is a COPY, not a symlink, on purpose: the /nextup + worktree workflow wants
# each worktree to inherit the root's USER-ZONE intent but keep its OWN local
# MACHINE ZONE (the "Where things stand" block, rebuilt per worktree from that
# worktree's specs). A symlink would share the machine zone across every
# worktree and defeat that — so we seed a real file the worktree can diverge.
#
# Use this (or `make worktree name=<name>`) instead of a bare `git worktree add`:
# a raw `git worktree add` will NOT bring nextup.md across — the git-lfs-owned
# post-checkout hook is the only hook that fires and we deliberately do not
# extend it (git-lfs overwrites it on reinstall).
#
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

# Seed the root's gitignored nextup.md into the new worktree as an independent
# copy (see header: shared user-zone intent, local machine zone).
if [ -e "$main_root/nextup.md" ]; then
    cp "$main_root/nextup.md" "$wt_dir/nextup.md"
    echo "copied nextup.md from $main_root/nextup.md"
else
    echo "note: no nextup.md in the main checkout to seed"
fi

echo "worktree ready: $wt_dir  [$branch]"
