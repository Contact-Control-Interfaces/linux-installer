#!/usr/bin/env bash
# =============================================================================
# plan.sh
# -----------------------------------------------------------------------------
# Works out the bundle's version and checks everything that must fail before
# any file is downloaded:
#
#   - VERSION holds X.Y.Z;
#   - on a tag: it is vX.Y.Z-rc.N or vX.Y.Z, its X.Y.Z equals VERSION, it sits
#     on main, Core and the Service are pinned in bundle.yaml, and a stable
#     bundle pins no prerelease component.
#
# Off a tag the version is X.Y.Z-ci.N and an unpinned required component only
# skips the rest of the workflow (ready=false).
#
#     tools/plan.sh                      # prints key=value lines
#     GITHUB_OUTPUT=... tools/plan.sh    # also writes them for later jobs
#
# Reads GITHUB_REF_TYPE, GITHUB_REF_NAME and GITHUB_RUN_NUMBER. Needs yq.
# =============================================================================
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "::error::$*" >&2; exit 1; }

command -v yq >/dev/null || fail "yq not found"

declared="$(tr -d '[:space:]' < "$root/VERSION")"
[[ "$declared" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION must hold X.Y.Z, found '$declared'"

pin() { yq -r ".components.$1.tag // \"\"" "$root/bundle.yaml"; }
core_tag="$(pin core)"
service_tag="$(pin service)"
manager_tag="$(pin manager)"

missing=()
[ -n "$core_tag" ] || missing+=(core)
[ -n "$service_tag" ] || missing+=(service)

prerelease=true
ready=true

if [ "${GITHUB_REF_TYPE:-}" = tag ]; then
    tag="${GITHUB_REF_NAME:?}"
    [[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)(-rc\.[0-9]+)?$ ]] \
        || fail "$tag is not vX.Y.Z-rc.N or vX.Y.Z"
    [ "${BASH_REMATCH[1]}" = "$declared" ] \
        || fail "$tag does not match VERSION ($declared). Bump VERSION on main first."
    git -C "$root" merge-base --is-ancestor "$tag" origin/main \
        || fail "$tag is not on main"
    [ ${#missing[@]} -eq 0 ] \
        || fail "bundle.yaml pins no release for: ${missing[*]}"
    version="${tag#v}"
    if [ -z "${BASH_REMATCH[2]}" ]; then
        prerelease=false
        for component_tag in "$core_tag" "$service_tag" "$manager_tag"; do
            [[ "$component_tag" != *-* ]] \
                || fail "a stable bundle can't pin the prerelease $component_tag"
        done
    fi
else
    version="$declared-ci.${GITHUB_RUN_NUMBER:-0}"
    if [ ${#missing[@]} -ne 0 ]; then
        ready=false
        echo "::warning::bundle.yaml pins no release for: ${missing[*]}. Nothing is collected or installed."
    fi
fi

{
    echo "version=$version"
    echo "prerelease=$prerelease"
    echo "ready=$ready"
    echo "core_tag=$core_tag"
    echo "service_tag=$service_tag"
    echo "manager_tag=$manager_tag"
} | tee -a "${GITHUB_OUTPUT:-/dev/null}"
