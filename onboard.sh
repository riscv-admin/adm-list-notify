#!/usr/bin/env bash
# Connect a repo to its group's mailing list.
#
#   ./onboard.sh [--prs] <owner/repo> <integration-address@lists.riscv.org>
#
# 1. Stores the address as the repo secret LIST_NOTIFY_EMAIL (never in the code).
# 2. Opens a pull request adding .github/workflows/notify-list.yml.
#    Default: new issues only. --prs: new issues and pull requests. On a repo that is
#    already connected for issues, --prs opens a PR that adds pull requests.
# Needs: gh CLI logged in with admin rights on the repo.
set -euo pipefail

usage="usage: onboard.sh [--prs] <owner/repo> <address@lists.riscv.org>"
prs=false
if [[ "${1:-}" == "--prs" ]]; then prs=true; shift; fi
repo="${1:?$usage}"
addr="${2:?$usage}"
[[ "$addr" =~ ^[A-Za-z0-9._+-]+@lists\.riscv\.org$ ]] || { echo "address must be @lists.riscv.org" >&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
path=".github/workflows/notify-list.yml"
if $prs; then
  template="$here/templates/notify-list-prs.yml"
  branch="add-notify-list-prs"
  what="an issue or pull request"
else
  template="$here/templates/notify-list.yml"
  branch="add-notify-list"
  what="an issue"
fi

gh secret set LIST_NOTIFY_EMAIL -R "$repo" -b "$addr"
echo "secret LIST_NOTIFY_EMAIL set on $repo"

existing_sha=""
if existing_sha="$(gh api "repos/$repo/contents/$path" --jq .sha 2>/dev/null)"; then
  if ! $prs; then
    echo "$path already exists on the default branch; secret updated only."
    exit 0
  fi
  if gh api "repos/$repo/contents/$path" --jq .content | base64 -d | grep -q pull_request_target; then
    echo "$path already sends pull requests; secret updated only."
    exit 0
  fi
  echo "$path exists (issues only); opening a PR to add pull requests."
else
  existing_sha=""
fi

base="$(gh api "repos/$repo" --jq .default_branch)"
sha="$(gh api "repos/$repo/git/ref/heads/$base" --jq .object.sha)"
gh api -X POST "repos/$repo/git/refs" -f ref="refs/heads/$branch" -f sha="$sha" >/dev/null
args=(-f message="Email the group's mailing list when $what is opened"
      -f branch="$branch"
      -f content="$(base64 < "$template" | tr -d '\n')")
[[ -n "$existing_sha" ]] && args+=(-f sha="$existing_sha")
gh api -X PUT "repos/$repo/contents/$path" "${args[@]}" >/dev/null
gh pr create -R "$repo" --base "$base" --head "$branch" \
  --title "Email the mailing list when $what is opened" \
  --body "Adds a small workflow that emails the group's mailing list whenever $what is opened, using the shared workflow in riscv-admin/adm-list-notify. The list address is stored in the repo secret LIST_NOTIFY_EMAIL."
