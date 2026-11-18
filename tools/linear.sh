#!/usr/bin/env bash
# =============================================================================
# linear.sh
# -----------------------------------------------------------------------------
# Records a bundle tag in Linear's "Linux SDK" release pipeline, so the issues
# that ship in a bundle are listed on its Linear release and close when it
# ships (dev-handbook, releases/versioning.md).
#
# A bundle ships the component releases pinned in bundle.yaml, so its issues
# are the ones referenced by the commits it brings in: in each component,
# from the tag the previous stable bundle pinned to the tag this one pins,
# and in this repository, from the previous stable bundle's tag to this one.
# linear-release finds them in commit messages, branch names and the pull
# requests the commits came from.
#
#   tag vX.Y.Z-rc.N   adds those issues to Linear release X.Y.Z, creating it
#   tag vX.Y.Z        adds any new ones, then completes release X.Y.Z
#
# Before the first stable bundle there is nothing to compare with, so the
# release is created or completed with no commits scanned. A component that
# the previous bundle didn't pin is not scanned either: its whole history is
# not this bundle's change.
#
#     tools/linear.sh <linear-release binary> [--dry-run]
#
# --dry-run scans and reads from Linear but changes nothing there.
#
# Reads GITHUB_REF_NAME (the bundle tag), LINEAR_ACCESS_KEY (the pipeline's
# access key) and GH_TOKEN (must read every pinned repository). Run from a
# full clone of this repository with its tags, checked out at the tag:
# linear-release scans up to HEAD. Needs git, gh and yq.
# =============================================================================
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
die() { echo "linear.sh: $*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: tools/linear.sh <linear-release binary> [--dry-run]"
cli="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
[ -x "$cli" ] || die "$1 is not an executable"
dry=()
[ "${2:-}" = --dry-run ] && dry=(--dry-run)

command -v gh >/dev/null || die "gh not found"
command -v yq >/dev/null || die "yq not found"
: "${LINEAR_ACCESS_KEY:?LINEAR_ACCESS_KEY is not set}"
export LINEAR_ACCESS_KEY

tag="${GITHUB_REF_NAME:?}"
[[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)(-rc\.[0-9]+)?$ ]] \
    || die "$tag is not vX.Y.Z-rc.N or vX.Y.Z"
version="${BASH_REMATCH[1]}"
stable=$([ -z "${BASH_REMATCH[2]}" ] && echo true || echo false)

# The newest stable bundle tag before this one. An rc of the same X.Y.Z is
# skipped, so a release lists everything since the last one customers got.
prev="$(git -C "$root" describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-rc.*' "$tag^" 2>/dev/null || true)"

pin() { # pin <bundle.yaml text> <component> <field>
    printf '%s\n' "$1" | yq -r ".components.$2.$3 // \"\""
}
now="$(git -C "$root" show "$tag:bundle.yaml")"
before=""
[ -z "$prev" ] || before="$(git -C "$root" show "$prev:bundle.yaml")"

# sync <directory> <base ref>: adds the issues in <base>..HEAD of the clone in
# <directory> to release X.Y.Z. A base of HEAD scans nothing.
sync() {
    (cd "$1" && "$cli" sync --release-version="$version" --base-ref="$2" ${dry[@]+"${dry[@]}"})
}

echo "Bundle $tag: Linear release $version, compared with ${prev:-nothing (no earlier stable bundle)}"

# This repository first: its sync creates the release if it doesn't exist.
sync "$root" "${prev:-HEAD}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for component in $(printf '%s\n' "$now" | yq -r '.components | keys | .[]'); do
    repo="$(pin "$now" "$component" repo)"
    new="$(pin "$now" "$component" tag)"
    old="$(pin "$before" "$component" tag)"
    if [ -z "$new" ]; then
        echo "$component: not pinned"; continue
    elif [ -z "$prev" ] || [ -z "$old" ]; then
        echo "$component: $new, not pinned before, so not scanned"; continue
    elif [ "$old" = "$new" ]; then
        echo "$component: still $new"; continue
    fi
    echo "$component: $repo $old..$new"
    gh repo clone "$repo" "$work/$component" -- --quiet --no-checkout
    git -C "$work/$component" checkout --quiet --detach "refs/tags/$new"
    if ! git -C "$work/$component" rev-parse --quiet --verify "refs/tags/$old^{commit}" >/dev/null; then
        echo "::warning::$repo has no tag $old any more, so its changes are not scanned"; continue
    fi
    sync "$work/$component" "refs/tags/$old"
done

if [ "$stable" = true ]; then
    (cd "$root" && "$cli" complete --release-version="$version" \
        --link "GitHub release=https://github.com/Contact-Control-Interfaces/linux-installer/releases/tag/$tag" \
        ${dry[@]+"${dry[@]}"})
fi
