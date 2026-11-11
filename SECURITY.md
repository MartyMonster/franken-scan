# Security reports

For a vulnerability, use GitHub's private vulnerability reporting if enabled, or email
hello@martymonster.dev. Do not include passwords, private keys or complete host reports.
For ordinary bugs, use the issue template with a redacted minimal reproduction.

The scanner is an aid, not a penetration test or proof of security. Its grade covers
only the checks performed. Skipped checks are unknown, even when the grade is A.

## Execution boundary

Run a downloaded copy only after checking its checksum and reading it. The script
prints suggested fixes but never executes them. It does not install packages, refresh
repositories, edit configuration or restart services. The optional report is created
exclusively: existing files and symlinks are refused.

RPM-family update front ends run with a timeout in a separate network namespace;
if this is unavailable the update query is skipped. DNF plugins are disabled. Package
tools can still write logs or package-cache bookkeeping, including RPM SQLite shared
memory. Ordinary file reads can update access times. This is not a whole-script
filesystem sandbox or a guarantee against compromised commands or network-mounted
configuration files. Use trusted local tools and local filesystems.

## Maintenance

Fixes target the latest released version. Distribution test coverage is listed in
SUPPORT.md; compatibility with a related distribution is not direct verification.
