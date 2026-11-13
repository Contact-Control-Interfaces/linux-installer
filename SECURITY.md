# Security

## Reporting a vulnerability

Please do not open a public issue or pull request for a security problem.

Report it privately through GitHub: on this repository's **Security** tab, choose [**Report a vulnerability**](https://github.com/Contact-Control-Interfaces/linux-installer/security/advisories/new). Only the maintainers and you can see the report.

If you cannot use GitHub, write to support@contactci.co and ask for a private channel. Leave the details out of that first message.

## What to report here

This repository is the public home of Contact CI software for Linux, so report here any problem in:

- the packages attached to its releases: the Service (`contactci-service`), Core (`libcontactci-core3`, `libcontactci-core-dev`) and the Manager (`contactci-manager`);
- this repository's scripts, test program or workflows.

## What helps

- The release you installed and the package versions (`dpkg -l | grep contactci`), and your Ubuntu release and architecture.
- What an attacker gains: for example root, the rights of the `contactci` user or group, or reading data they should not see.
- The smallest set of steps that shows the problem.
- Whether it needs a glove connected, and whether it needs membership of the `contactci` group or root to begin with.

A maintainer replies on the report. Please keep the details there until a fixed version is released.

## Checking a download

Download the packages only from this repository's [releases](https://github.com/Contact-Control-Interfaces/linux-installer/releases), together with that release's `SHA256SUMS.txt`, and check them before installing:

```sh
sha256sum --check --ignore-missing SHA256SUMS.txt
```
