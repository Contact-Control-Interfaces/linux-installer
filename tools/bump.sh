#!/usr/bin/env bash
# =============================================================================
# bump.sh
# -----------------------------------------------------------------------------
# Moves each pin in bundle.yaml to its component's newest stable release, when
# that release:
#
#   - is tagged vX.Y.Z and is neither a draft nor a prerelease;
#   - is a later version than the pin (X.Y.Z follows its own X.Y.Z-rc.N), or
#     the component has no pin yet;
#   - has that component's Linux package attached.
#
# It never moves a pin back and never pins a release candidate: those are
# pinned by hand. VERSION is left alone. Nothing is committed or published;
# the `bump` workflow turns the edit into a pull request.
#
#     tools/bump.sh [body-file]          # edits bundle.yaml, prints what moved
#     GITHUB_OUTPUT=... tools/bump.sh    # also writes changed and title
#
# body-file, when given and a pin moved, receives the pull request's text.
# GH_TOKEN must be able to read every component repository's releases.
# Needs gh and yq.
# =============================================================================
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
body="${1:-}"
die() { echo "bump.sh: $*" >&2; exit 1; }

command -v gh >/dev/null || die "gh not found"
command -v yq >/dev/null || die "yq not found"

field() { yq -r ".components.$1.$2 // \"\"" "$root/bundle.yaml"; }

# package <component>: the asset a release must have to be installable on Linux.
package() {
    case "$1" in
        core)    echo '^libcontactci-core[0-9]+_.*\.deb$' ;;
        service) echo '^contactci-service_.*\.deb$' ;;
        manager) echo '^contactci-manager_.*\.deb$' ;;
        *)       die "bundle.yaml has a component this script doesn't know: $1" ;;
    esac
}

# name <component>: what the README calls it.
name() {
    case "$1" in
        core) echo Core ;; service) echo Service ;; manager) echo Manager ;;
    esac
}

# later <stable-tag> <pinned-tag>: the stable tag is a later version than the
# pin. An empty pin is earlier than everything.
later() {
    local candidate="${1#v}" pinned="${2#v}" pinned_core
    [ -n "$pinned" ] || return 0
    pinned_core="${pinned%%-*}"
    if [ "$candidate" = "$pinned_core" ]; then
        [ "$pinned" != "$pinned_core" ]
        return
    fi
    [ "$(printf '%s\n' "$candidate" "$pinned_core" | sort -V | tail -n 1)" = "$candidate" ]
}

# newest <component>: prints the newest stable release that is later than the
# pin and has the component's Linux package, or nothing.
newest() {
    local component="$1" repo pinned pattern tags tag assets
    repo="$(field "$component" repo)"
    pinned="$(field "$component" tag)"
    pattern="$(package "$component")"
    tags="$(gh release list --repo "$repo" --exclude-drafts --exclude-pre-releases --limit 100 \
                --json tagName --jq '.[].tagName')" \
        || die "could not list the releases of $repo"
    # Newest first, so the first tag that isn't later than the pin ends the search.
    while read -r tag; do
        [ -n "$tag" ] || continue
        later "$tag" "$pinned" || break
        assets="$(gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name')" \
            || die "could not read $repo $tag"
        if grep -Eq "$pattern" <<<"$assets"; then
            echo "$tag"
            return
        fi
        echo "$component: $tag has no Linux package, skipped" >&2
    done < <(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$tags" | sort -rV)
}

titles=()
rows=()
for component in $(yq -r '.components | keys | .[]' "$root/bundle.yaml"); do
    package "$component" >/dev/null
    pinned="$(field "$component" tag)"
    tag="$(newest "$component")"
    if [ -z "$tag" ]; then
        echo "$component: ${pinned:-unpinned}, nothing newer"
        continue
    fi
    TAG="$tag" yq -i ".components.$component.tag = strenv(TAG)" "$root/bundle.yaml"
    echo "$component: ${pinned:-unpinned} -> $tag"
    titles+=("$(name "$component") $tag")
    was="none"
    [ -z "$pinned" ] || was="\`$pinned\`"
    rows+=("| $(name "$component") | $was | \`$tag\` |")
done

if [ ${#titles[@]} -eq 0 ]; then
    echo "changed=false" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
fi

title="Pin $(printf '%s, ' "${titles[@]}")"
title="${title%, }"
{
    echo "changed=true"
    echo "title=$title"
} >> "${GITHUB_OUTPUT:-/dev/null}"
echo "$title"

if [ -n "$body" ]; then
    {
        echo "Each of these components has a stable release later than its pin, with Linux packages:"
        echo
        echo "| Component | Was | Now |"
        echo "| -- | -- | -- |"
        printf '%s\n' "${rows[@]}"
        echo
        echo "Opened by the \`bump\` workflow, which also started the \`release\` workflow on this branch. That run installs this set on every supported machine and opens a Session through Core against the Service; it does nothing while the Service is unpinned. Merge only when it has passed."
        echo
        echo "\`VERSION\` is not changed. Change it in this pull request if the bundle's own version should move. Merging publishes nothing: a release still needs a tag."
        echo
        echo "To decline this bump, close the pull request and keep its branch."
    } > "$body"
fi
