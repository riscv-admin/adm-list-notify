#!/usr/bin/env bash
# Connect a repo to its group's mailing list.
#
#   ./onboard.sh <owner/repo> <integration-address@lists.riscv.org>
#
# 1. Stores the address as the repo secret LIST_NOTIFY_EMAIL (never in the code).
# 2. Opens a pull request adding .github/workflows/notify-list.yml.
# Needs: gh CLI logged in with admin rights on the repo.
set -euo pipefail

repo="${1:?usage: onboard.sh <owner/repo> <address@lists.riscv.org>}"
addr="${2:?usage: onboard.sh <owner/repo> <address@lists.riscv.org>}"
[[ "$addr" =~ ^[A-Za-z0-9._+-]+@lists\.riscv\.org$ ]] || { echo "address must be @lists.riscv.org" >&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
path=".github/workflows/notify-list.yml"
branch="add-notify-list"

gh secret set LIST_NOTIFY_EMAIL -R "$repo" -b "$addr"
echo "secret LIST_NOTIFY_EMAIL set on $repo"

if gh api "repos/$repo/contents/$path" >/dev/null 2>&1; then
  echo "$path already exists on the default branch; secret updated only."
  exit 0
fi

base="$(gh api "repos/$repo" --jq .default_branch)"
sha="$(gh api "repos/$repo/git/ref/heads/$base" --jq .object.sha)"
gh api -X POST "repos/$repo/git/refs" -f ref="refs/heads/$branch" -f sha="$sha" >/dev/null
gh api -X PUT "repos/$repo/contents/$path" \
  -f message="Email the group's mailing list when an issue is opened" \
  -f branch="$branch" \
  -f content="$(base64 < "$here/templates/notify-list.yml" | tr -d '\n')" >/dev/null
gh pr create -R "$repo" --base "$base" --head "$branch" \
  --title "Email the mailing list when an issue is opened" \
  --body "Adds a small workflow that emails the group's mailing list whenever a new issue is opened, using the shared workflow in riscv-admin/adm-list-notify. The list address is stored in the repo secret LIST_NOTIFY_EMAIL."
