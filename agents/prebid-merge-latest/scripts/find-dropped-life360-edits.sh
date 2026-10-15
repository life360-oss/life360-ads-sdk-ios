#!/usr/bin/env bash
# Lists files Life360 modified that upstream deletes — usually ObjC classes upstream rewrote in
# Swift. Git resolves these as modify/delete, and accepting the delete silently drops the Life360
# edit, so each one needs porting into its Swift replacement.
#
# Usage: find-dropped-life360-edits.sh [ours] [theirs]
#   ours   defaults to HEAD (the Life360 side, before merging)
#   theirs defaults to prebid/master
#
# Prints one line per file: "<changed-line-count> <path>", largest first.
set -euo pipefail

ours="${1:-HEAD}"
theirs="${2:-prebid/master}"
base="$(git merge-base "$ours" "$theirs")"

modified_by_ours="$(mktemp)"
deleted_by_theirs="$(mktemp)"
trap 'rm -f "$modified_by_ours" "$deleted_by_theirs"' EXIT

git diff --name-only --diff-filter=M "$base" "$ours" | sort > "$modified_by_ours"
git diff --name-only --diff-filter=D "$base" "$theirs" | sort > "$deleted_by_theirs"

comm -12 "$modified_by_ours" "$deleted_by_theirs" | while IFS= read -r path; do
    changed="$(git diff "$base" "$ours" -- "$path" | grep -c '^[-+][^-+]' || true)"
    echo "$changed $path"
done | sort -rn
