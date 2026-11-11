# Changelog

## v1.1.0 — 2026-11-11

- Add repeatable distro-container and booted-VM verification, including ARM64.
- Preserve failed command results; missing caches and unsupported checks stay incomplete.
- Query DNF4/DNF5 with plugins disabled, explicit package formatting and network isolation.
- Parse zypper XML with optional Python; distinguish Tumbleweed from Leap update advice.
- Recognise pacman's empty-upgrade status without treating diagnostics as success.
- Stop claiming automatic updates or firewall protection from service presence alone.
- Treat non-loopback listeners honestly; do not assume Docker/VPN subnet names are safe.
- Preserve failed listener, clock and system-file probes as unknown results.
- Create reports with owner-only permissions; add overwrite/symlink regression checks and clearer scope documentation.

## v1.0.1

Initial review fixes, terminal artwork and --monster option. See CODEX-REVIEW.md for
the historical review and its original context.

## v1.0.0

Initial public release.
