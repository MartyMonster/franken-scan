# Compatibility and evidence

One downloadable Bash script. Native .deb/.rpm/Arch packages are not part of v1.1.
Bash 4+ and standard Linux utilities (including awk, grep, sed, find and coreutils)
are required. Missing mandatory tools produce a clear error with exit status 2.
Optional tools are skipped rather than installed by the scanner.

## Automated matrix

| Distribution | Release | Architecture | Container scan |
|---|---|---|---|
| Debian | 12, 13 | x86_64 | Root and unprivileged |
| Debian | 13 | ARM64 | Root and unprivileged |
| Ubuntu | 24.04, 26.04 | x86_64 | Root and unprivileged |
| Arch Linux | Rolling image, digest recorded per run | x86_64 | Root and unprivileged |
| Fedora | 44 | x86_64 | Root and unprivileged |
| Rocky Linux | 9 | x86_64 | Root and unprivileged |
| AlmaLinux | 9 | x86_64 | Root and unprivileged |
| openSUSE Leap | 16.0 | x86_64 | Root and unprivileged |
| openSUSE Tumbleweed | Rolling image, digest recorded per run | x86_64 | Root and unprivileged |

The [Distro verification workflow](https://github.com/MartyMonster/franken-scan/actions/workflows/distros.yml)
records image digests, complete scan logs and filesystem differences. Tests check
root and unprivileged completion, failed probes, report preservation, symlink refusal,
and unchanged contents of regular configuration files under /etc. Preparation downloads
packages; the actual container scans have no external network.

Booted Debian 13, Fedora 44 and Leap 16 cloud-image validation is a separate
[VM workflow](https://github.com/MartyMonster/franken-scan/actions/workflows/virtual-machines.yml).
All three booted guests passed at commit dd6bf06 (run 43002608077). Release commits
are checked again before publication; container success alone does not establish
booted-service coverage. Guest images run in unprivileged QEMU with restricted user networking and
no host directory mounts. Image hashes and serial logs are retained per run.

## Limits that matter

- RHEL, Omarchy, Manjaro and other derivatives are inferred compatibility, not direct
  verification. ARM64 Debian does not prove support for every Raspberry Pi/RockPi OS.
- Non-systemd hosts can run general checks, but service checks are incomplete. Alpine,
  Void and immutable/transactional variants are not verified targets.
- Package checks use existing metadata only. A missing cache is unknown, not up to date.
  No security-origin classification is inferred from repository display names.
- DNF4/DNF5 and zypper queries require `unshare`, `timeout` and permission to create a
  network namespace. They are skipped otherwise. Zypper XML parsing needs Python 3.
- Ufw default policy is inspected. Other firewall managers are described conservatively;
  rules across interfaces, routing and both IP families need a fuller audit.
- SSH checks use default `sshd -T` output, not every Match context or custom daemon
  invocation. Non-loopback listeners are not proof of internet exposure.
- An active update timer does not prove installation policy or recent successful updates.
- Package tools may update logs and cache bookkeeping. See SECURITY.md.

Exit 0 means no HIGH findings, not a complete or secure system; exit 1 means HIGH
findings; exit 2 covers invalid invocation or missing mandatory utilities. Review the
skipped count and report as well as the exit status.
