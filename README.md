# Contact CI for Linux

Contact CI software for Linux, as `.deb` packages for Ubuntu on amd64 and arm64. Each [release](https://github.com/Contact-Control-Interfaces/linux-installer/releases) is one set of versions that were installed and tested together:

| Package | What it is |
| -- | -- |
| `contactci-service` | The Service: a background (systemd) service that owns the gloves connected over USB or Bluetooth. |
| `libcontactci-core3` | Core: the libraries an application uses to reach the gloves through the Service. |
| `libcontactci-core-dev` | The C API header (`contactci.h`) and the `libccic.so` link, for building your own application. |
| `contactci-manager` | The Manager: a desktop application that shows the Service, gloves and connected applications. Not in every release. |

> **Status:** no release has been published yet.

## Supported machines

| Machine | Ubuntu | File suffix |
| -- | -- | -- |
| amd64 | 22.04 | `_ubuntu22.04_amd64` |
| amd64 | 24.04 | `_ubuntu24.04_amd64` |
| Jetson Orin on JetPack 6 | 22.04 | `_ubuntu22.04_arm64` |
| Jetson Orin on JetPack 7.2, or Jetson Thor | 24.04 | `_ubuntu24.04_arm64` |

The Manager has one package per architecture (`_amd64`, `_arm64`) that installs on both Ubuntu releases.

## Install

1. From the [latest release](https://github.com/Contact-Control-Interfaces/linux-installer/releases), download the files whose names end with your machine's suffix, and `SHA256SUMS.txt`.

2. Check the downloads:

   ```sh
   sha256sum --check --ignore-missing SHA256SUMS.txt
   ```

3. Install the Service and Core, here for Ubuntu 24.04 on amd64:

   ```sh
   sudo apt install ./contactci-service_*_ubuntu24.04_amd64.deb ./libcontactci-core3_*_ubuntu24.04_amd64.deb ./libcontactci-core-dev_*_ubuntu24.04_amd64.deb
   ```

   Leave out `libcontactci-core-dev` on a machine that only runs applications. Add `./contactci-manager_*_amd64.deb` for the Manager.

4. Let your user use the gloves, then log out and back in:

   ```sh
   sudo usermod -aG contactci $USER
   ```

Installing creates the `contactci` user and group, gives that group access to USB gloves, and enables and starts `contactci.service`. Bluetooth gloves must be paired first, for example with `bluetoothctl`; the Service finds paired gloves by itself.

Upgrading is the same `apt install` with the newer files. Install the Service and Core from the same release: they check each other's protocol version when an application connects, and a mismatched pair refuses the connection.

## Check that it works

```sh
systemctl status contactci
journalctl -u contactci -f
```

A glove plugging in shows up in the log as `Available: …` and then `Connected Device for the … hand: …`.

[`tests/smoke.c`](tests/smoke.c) is a small C program that opens a Session through Core. It needs no glove:

```sh
gcc tests/smoke.c -o smoke -lccic
./smoke
```

`Failed to open pipe` means the Service is not running. A permission error means your user is not in the `contactci` group yet, or has not logged in again since being added.

## Build against Core

Include `<contactci.h>` and link with `-lccic`. `tests/smoke.c` shows the calls that open a Session and reach the haptic state.

Without `dpkg`, each release also has `contactci-core_*.tar.gz`: the same libraries and headers as the two Core packages, as an install tree. There is no Service package for other distributions.

## Remove

```sh
sudo apt remove contactci-service libcontactci-core3 libcontactci-core-dev
```

Use `purge` to drop the Service's systemd state as well. The `contactci` user and group stay behind, as is usual for system accounts; `sudo userdel contactci` removes them.

## Licence and support

The packages are proprietary software, distributed under the [Contact CI SDK EULA](https://contact.ci/pages/sdk-eula). Third-party components and their licences are listed in `/usr/share/doc/` for each installed package. See [LICENSE.md](LICENSE.md).

Questions and problems: support@contactci.co.

## For maintainers: cutting a release

This repository builds nothing. [`bundle.yaml`](bundle.yaml) pins one release tag of each component, and the [`release` workflow](.github/workflows/release.yml) downloads those releases' files, checks them against the checksums each release published, installs them on every supported machine, opens a Session through Core against the running Service, and republishes the same files.

1. In a pull request, set the tags in `bundle.yaml`, and `VERSION` if the bundle's own version moves. The pull request runs everything except the publish.
2. After it merges, tag the commit on `main`: `vX.Y.Z-rc.N` for a prerelease, `vX.Y.Z` for a release. A stable bundle may pin only stable component releases.

```sh
git tag -a v0.1.0-rc.1 -m "0.1.0-rc.1"
git push origin v0.1.0-rc.1
```

Tags and versions are permanent: a broken release candidate is fixed by the next `rc.N`, a broken release by the next patch version.
