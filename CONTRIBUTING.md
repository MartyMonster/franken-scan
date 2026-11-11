# Contributing

Keep franken-scan useful to people who are not Linux experts: explain the observation,
why it matters, and a distro-appropriate next step. Never execute suggested fixes.

## Local checks

```bash
bash -n franken-scan.sh
shellcheck franken-scan.sh tests/container.sh tests/vm-guest.sh
bash tests/portability.sh
bash tests/detection.sh
git diff --check
```

Add a regression fixture for changed detection/parsing, including command failures,
missing tools and empty input. Unknown results must remain skipped, not become passes.
Keep the downloadable scanner in one file; optional dependencies must degrade clearly.

## Integration checks

GitHub Actions prepares disposable distro containers with network access, then runs
scans with networking disabled. Booted-service checks use separate unprivileged QEMU
cloud guests with restricted user networking, no host mounts and no credentials.
These are test environments, not targets for the scanner to modify.

Check the scan logs and evidence artifacts, not just workflow badges. Never run new
root-level checks on a real machine as a substitute for isolated tests. Do not include
private hostnames, account lists, network layouts or credentials in public reports.

## Releases

Use semantic versions and keep CLI compatibility unless a major release explicitly
changes it. Update CHANGELOG.md and SUPPORT.md with exact coverage and limitations.
Run the full matrix on the final code, then tag that tested commit. Generate the checksum
from the release script, upload both files, download them again and verify the checksum.
Update the website only after its download links work. Previous release assets remain
available for rollback; do not silently replace them.
