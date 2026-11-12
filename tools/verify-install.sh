#!/usr/bin/env bash
# =============================================================================
# verify-install.sh
# -----------------------------------------------------------------------------
# Installs this machine's packages from a collected bundle the way the README
# tells a user to, then checks what they rely on:
#
#   1. the Service is enabled and running under systemd;
#   2. a C program built against the dev package opens a Session, as a user
#      whose only extra group is contactci (tests/smoke.c);
#   3. the Service reports the version the bundle pins;
#   4. the Manager, when the bundle has one, installs beside them;
#   5. everything removes cleanly.
#
# Needs systemd and sudo, so it runs on a real machine or a CI runner, not in
# a plain container. It installs and removes packages on the host.
#
#     tools/verify-install.sh <bundle-dir> <service-version>
# =============================================================================
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="$(cd "${1:?usage: verify-install.sh <bundle-dir> <service-version>}" && pwd)"
service_version="${2:?usage: verify-install.sh <bundle-dir> <service-version>}"
die() { echo "verify-install.sh: $*" >&2; exit 1; }

ubuntu="$(. /etc/os-release && echo "$VERSION_ID")"
arch="$(dpkg --print-architecture)"
suffix="ubuntu${ubuntu}_${arch}"
echo "== $suffix"

(cd "$bundle" && sha256sum --check --quiet SHA256SUMS.txt) || die "the bundle's checksums don't match"

shopt -s nullglob
packages=("$bundle"/contactci-service_*_"$suffix".deb
          "$bundle"/libcontactci-core[0-9]*_"$suffix".deb
          "$bundle"/libcontactci-core-dev_*_"$suffix".deb)
manager=("$bundle"/contactci-manager_*_"$arch".deb)
shopt -u nullglob
[ ${#packages[@]} -eq 3 ] || die "expected the Service, Core and Core dev packages for $suffix, found ${#packages[@]}"

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq "${packages[@]}" gcc libc6-dev

echo "== the Service"
systemctl is-enabled contactci || die "contactci.service isn't enabled"
for _ in $(seq 1 20); do systemctl is-active --quiet contactci && break; sleep 0.5; done
systemctl is-active contactci || { sudo journalctl -u contactci --no-pager | tail -n 20; die "contactci.service isn't running"; }

echo "== a Session through Core"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
gcc -Wall -Wextra "$root/tests/smoke.c" -o "$work/smoke" -lccic
chmod 755 "$work" "$work/smoke"
# As this user with contactci as the only group: what `usermod -aG contactci` gives a user.
sudo setpriv --reuid="$(id -u)" --regid=contactci --clear-groups "$work/smoke" "$service_version" \
    || { sudo journalctl -u contactci --no-pager | tail -n 20; die "the smoke Session failed"; }

if [ ${#manager[@]} -eq 1 ]; then
    echo "== the Manager"
    sudo apt-get install -y -qq "${manager[0]}"
    [ -x /usr/bin/contactci-manager ] || die "the Manager package didn't install /usr/bin/contactci-manager"
    sudo apt-get purge -y -qq contactci-manager
fi

echo "== removal"
sudo apt-get purge -y -qq contactci-service libcontactci-core-dev "$(dpkg-deb -f "${packages[1]}" Package)"
! systemctl is-active --quiet contactci || die "contactci.service is still running after removal"
echo "bundle ok on $suffix"
