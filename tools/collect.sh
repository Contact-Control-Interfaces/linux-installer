#!/usr/bin/env bash
# =============================================================================
# collect.sh
# -----------------------------------------------------------------------------
# Downloads the release assets of every component pinned in bundle.yaml,
# checks each file against the checksums its own release published, and
# writes the bundle's files and one SHA256SUMS.txt to the output directory.
# A component with an empty tag is skipped; tools/plan.sh decides whether
# that is allowed.
#
# Files keep the names their release gave them, except the Service's, which
# are renamed to Core's scheme so one suffix picks a machine's files:
#
#     contactci-service_<version>_ubuntu<22.04|24.04>_<amd64|arm64>.deb
#
#     tools/collect.sh [output-dir]      # default dist
#
# GH_TOKEN must be able to read every pinned repository's releases.
# Needs gh and yq.
# =============================================================================
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-dist}"
die() { echo "collect.sh: $*" >&2; exit 1; }

command -v gh >/dev/null || die "gh not found"
command -v yq >/dev/null || die "yq not found"

mkdir -p "$out"
out="$(cd "$out" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

field() { yq -r ".components.$1.$2 // \"\"" "$root/bundle.yaml"; }

# fetch <component> <pattern>...: downloads the matching assets of the pinned
# release into $work/<component>. Prints nothing; fails if the tag is missing.
fetch() {
    local component="$1"; shift
    local repo tag patterns=()
    repo="$(field "$component" repo)"
    tag="$(field "$component" tag)"
    for pattern in "$@"; do patterns+=(--pattern "$pattern"); done
    mkdir -p "$work/$component"
    echo "== $component: $repo $tag"
    gh release download "$tag" --repo "$repo" --dir "$work/$component" "${patterns[@]}" \
        || die "could not download $component $tag from $repo"
}

# verified <component> <file>: the file's SHA-256 must be one its release
# published. Compared by hash, not by name: a release may rename an asset.
verified() {
    local component="$1" file="$2" hash
    hash="$(sha256sum "$file" | cut -d' ' -f1)"
    cat "$work/$component"/SHA256SUMS*.txt | tr -d '\r' | tr '[:upper:]' '[:lower:]' \
        | grep -q "^$hash " \
        || die "$(basename "$file") is not in the checksums $component published"
}

# one <glob>: the single file the glob matches, or fail.
one() {
    local matches=()
    shopt -s nullglob
    # shellcheck disable=SC2206  # the glob is meant to expand
    matches=($1)
    shopt -u nullglob
    [ ${#matches[@]} -eq 1 ] || die "expected one file matching $1, found ${#matches[@]}"
    echo "${matches[0]}"
}

targets=("22.04 amd64" "22.04 arm64" "24.04 amd64" "24.04 arm64")

# --- Core: runtime .deb, dev .deb and a tarball per Ubuntu release and arch --
if [ -n "$(field core tag)" ]; then
    fetch core 'libcontactci-core*.deb' 'contactci-core_*.tar.gz' 'SHA256SUMS.txt'
    for target in "${targets[@]}"; do
        read -r ubuntu arch <<<"$target"
        for glob in "libcontactci-core[0-9]*_ubuntu${ubuntu}_${arch}.deb" \
                    "libcontactci-core-dev_*_ubuntu${ubuntu}_${arch}.deb" \
                    "contactci-core_*_ubuntu${ubuntu}_${arch}.tar.gz"; do
            file="$(one "$work/core/$glob")"
            verified core "$file"
            cp "$file" "$out/"
        done
    done
fi

# --- Service: one .deb per runner image, named <...>_<runner>.deb ------------
if [ -n "$(field service tag)" ]; then
    fetch service 'contactci-service_*.deb' 'SHA256SUMS-*.txt'
    service_version="$(field service tag)"; service_version="${service_version#v}"
    for target in "${targets[@]}"; do
        read -r ubuntu arch <<<"$target"
        runner="ubuntu-$ubuntu"; [ "$arch" = arm64 ] && runner+="-arm"
        file="$(one "$work/service/contactci-service_*_${runner}.deb")"
        verified service "$file"
        cp "$file" "$out/contactci-service_${service_version}_ubuntu${ubuntu}_${arch}.deb"
    done
fi

# --- Manager: one .deb per architecture, for every supported Ubuntu ----------
if [ -n "$(field manager tag)" ]; then
    fetch manager '*.deb' 'SHA256SUMS.txt'
    for arch in amd64 arm64; do
        file="$(one "$work/manager/*_${arch}.deb")"
        verified manager "$file"
        cp "$file" "$out/"
    done
fi

(cd "$out" && rm -f SHA256SUMS.txt && sha256sum -- * > "$work/SHA256SUMS.txt")
mv "$work/SHA256SUMS.txt" "$out/SHA256SUMS.txt"
echo "== bundle"
cat "$out/SHA256SUMS.txt"
