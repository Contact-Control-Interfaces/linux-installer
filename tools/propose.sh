#!/usr/bin/env bash
# =============================================================================
# propose.sh
# -----------------------------------------------------------------------------
# Turns the edit tools/bump.sh made to bundle.yaml into the bump pull request,
# and makes sure the release workflow has run on it. Run from a checkout of
# main; the `bump` workflow is its only caller.
#
# What it does depends on the bump branch (bump/stable-pins):
#
#   - no branch, or one holding older pins made only by this workflow:
#     the branch is rebuilt from main with the new pins, and its pull request
#     is opened or updated;
#   - the branch already holds these pins: nothing is pushed. A missing pull
#     request or release run is an earlier run that failed part-way, and is
#     finished, unless a pull request for that same commit was closed: that is
#     a declined bump, and it is left alone;
#   - the branch holds other pins and someone has added commits to it: it is
#     left alone, with one comment on its pull request saying so.
#
#     tools/propose.sh <title> <body-file>
#
# GH_TOKEN must be able to push the branch, write pull requests and start
# workflows in this repository. Needs gh.
# =============================================================================
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
title="${1:?usage: propose.sh <title> <body-file>}"
body="${2:?usage: propose.sh <title> <body-file>}"
branch="${BUMP_BRANCH:-bump/stable-pins}"
bot_name="github-actions[bot]"
bot_email="41898282+github-actions[bot]@users.noreply.github.com"
die() { echo "propose.sh: $*" >&2; exit 1; }

command -v gh >/dev/null || die "gh not found"
[ -f "$body" ] || die "$body not found"
cd "$root"
! git diff --quiet -- bundle.yaml || die "bundle.yaml has no edit to propose"

# Whose commits are on the branch is read from history, so all of it is needed.
if [ "$(git rev-parse --is-shallow-repository)" = true ]; then
    git fetch --quiet --unshallow origin
fi

head=""
if git fetch --quiet origin "$branch" 2>/dev/null; then
    head="$(git rev-parse FETCH_HEAD)"
fi
pr="$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty')"

# check <commit>: starts the release workflow on the branch unless that commit
# already has a run. A pull request opened with the workflow token starts no
# workflows by itself; the run still shows on the pull request.
check() {
    local runs
    runs="$(gh run list --workflow release.yml --commit "$1" --json databaseId --jq 'length')"
    if [ "$runs" = 0 ]; then
        gh workflow run release.yml --ref "$branch"
        echo "Started the release workflow on $branch."
    fi
}

open() {
    gh pr create --base main --head "$branch" --title "$title" --body-file "$body"
}

if [ -n "$head" ] && git diff --quiet FETCH_HEAD -- bundle.yaml; then
    if [ -n "$pr" ]; then
        echo "Pull request #$pr already proposes these pins."
    else
        declined="$(gh pr list --head "$branch" --state all --json headRefOid,state \
            --jq "[.[] | select(.state == \"CLOSED\" and .headRefOid == \"$head\")] | length")"
        if [ "$declined" != 0 ]; then
            echo "These pins were declined: a pull request for $branch at ${head::7} was closed. Nothing to do."
            exit 0
        fi
        echo "$branch holds these pins but has no pull request. Opening it."
        open
    fi
    check "$head"
    exit 0
fi

if [ -n "$head" ]; then
    others="$(git log --format=%ae "HEAD..FETCH_HEAD" | grep -vxF "$bot_email" || true)"
    if [ -n "$others" ]; then
        echo "::warning::$title is available, but $branch has commits this workflow did not make. It was left alone."
        if [ -n "$pr" ]; then
            comments="$(gh pr view "$pr" --json comments --jq '.comments[].body')"
            if ! grep -qF "$title" <<<"$comments"; then
                gh pr comment "$pr" --body "Newer pins are available: **$title**. This branch has commits the \`bump\` workflow did not make, so it was left alone. Run \`tools/bump.sh\` on this branch to take them, or close this pull request and delete the branch to get a fresh one."
            fi
        fi
        exit 0
    fi
fi

git switch --quiet --force-create "$branch"
git -c user.name="$bot_name" -c user.email="$bot_email" commit --quiet --message "$title" -- bundle.yaml
git push --quiet --force origin "$branch"
if [ -n "$pr" ]; then
    gh pr edit "$pr" --title "$title" --body-file "$body"
else
    open
fi
check "$(git rev-parse HEAD)"
