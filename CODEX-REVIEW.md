# franken-scan.sh — second-opinion review

> **Reviewer:** OpenAI Codex (GPT6ASTRA), an independent review requested before v1.0.1.
> Kept here, unedited below, for transparency.
>
> **What changed in v1.0.1 because of it:** symlink-safe, create-only `--report` (1); honest promise
> wording (2, 9); `/etc/group` and `os-release` read as plain text (3, 8); the firewall passes only on a
> real drop/deny policy (4); SSH checks the keyboard-interactive/PAM route and every `PermitRootLogin`
> value (5); SSH is verified only via `sshd -T` as root, otherwise skipped (6); failed commands are
> reported as skipped and incomplete scans are labelled (7); per-distro, port-aware fix advice (12);
> only uncommented apt settings count, and fail2ban needs an SSH jail (13); Docker other-write bit (14);
> `find -H` for symlinked system folders (15). Items 10, 11, 16 and 17 and the missing checks are
> planned for v1.1.


Reviewed 9 November 2026 on omarchy-hp-omen. Line numbers refer to the existing, locally modified 740-line script, SHA-256 `bfec2ef3de1b08a3ee5f0c4ed3d86a82ae9d58d0bcc1ae02e2be313628fbd008`. The script was not executed or edited. `bash -n` and ShellCheck both pass; these do not establish runtime correctness. Cross-distribution findings below are static analysis, not claims of testing on six distributions.

## Findings, most important first

### 1. HIGH — Report output can overwrite arbitrary files as root
**Lines 69–75, 681–700.** `> "$REPORT_FILE"` creates/truncates a file and follows symlinks. A predictable default filename in a directory writable by someone else permits a pre-planted symlink to a privileged file. Quoting prevents splitting, but not this attack. Even ordinary successful reporting contradicts the absolute no-change promise and the report's own assertion at line 697.
**Suggested fix:** For the stated strict promise, remove file output and emit Markdown to stdout for the caller to redirect as an unprivileged user. If report writes are deliberately retained, explicitly change the promise and use exclusive creation in a trusted directory; never overwrite an existing path or follow a report symlink.

### 2. HIGH — “Cache only” package queries are not a no-write sandbox
**Lines 391, 393.** DNF can write logs and load installed plugins even with `-C`; zypper normally writes `/var/log/zypper.log`, and `--no-refresh` only disables repository refresh. Neither invocation establishes that all plugin/library behaviour is offline and read-only. This is a normal-operation problem, not just an attacker-controlled filename scenario.
**Suggested fix:** Under the absolute promise, skip these front ends until their exact versions and configuration have a verified, constrained offline/read-only path, or inspect existing metadata without executing plugin-capable managers. Merely redirecting stderr or adding a cache option is insufficient. A stronger guarantee needs enforced filesystem/network isolation and explicit handling of unsupported environments.
Sources: [DNF configuration](https://dnf.readthedocs.io/en/latest/conf_ref.html), [zypper manual](https://manpages.opensuse.org/Tumbleweed/zypper/zypper.8.en.html).

### 3. HIGH — Group lookups can use the network
**Lines 487, 526.** `getent group` follows NSS configuration. LDAP/NIS/SSSD/winbind-backed groups can cause remote requests, including requests made by a local daemon on the script's behalf. These are not guaranteed local file reads.
**Suggested fix:** Parse `/etc/group` and `/etc/passwd` directly and label the results local-only. Do not replace these with unrestricted NSS lookups elsewhere. Network namespace isolation alone does not stop an existing host daemon from making a delegated request.

### 4. HIGH — Firewall detection can pass a completely permissive ruleset
**Lines 287–302.** Any `iptables -A INPUT` rule passes, even `-A INPUT -j ACCEPT` with policy ACCEPT. The nft expression matches ordinary rules in output, forwarding or NAT chains, including Docker rules, without proving input filtering. An active firewalld service can have a trusted/accept zone; an active oneshot ufw/nftables unit can outlive flushed rules. IPv4 iptables alone says nothing about IPv6.
**Suggested fix:** Separate “manager/service present” from verified host filtering. Inspect applicable input hooks, policies, reachable jumps, interfaces/zones and both IP families. If effective protection cannot be determined, say unknown; do not award a firewall pass from service state or any rule's existence.

### 5. HIGH — Disabling PasswordAuthentication does not prove keys-only SSH
**Lines 253–272.** PAM-backed keyboard-interactive authentication may still accept passwords when `PasswordAuthentication no`. Conversely `PermitRootLogin yes` does not prove root can authenticate with a password if password routes are disabled or the account is locked. `forced-commands-only` is incorrectly classified as password root login. `AuthenticationMethods` can also require multiple factors.
**Suggested fix:** Report individual effective controls, including keyboard-interactive/PAM and AuthenticationMethods, with explicit uncertainty about account/PAM policy. Handle every documented PermitRootLogin value; reserve “keys only” for settings that actually support that conclusion. [OpenSSH settings](https://man.archlinux.org/man/sshd_config.5.en).

### 6. HIGH — SSH fallback ignores Include ordering and Match scope
**Lines 236–250, 277–278.** Concatenating the main file then every default snippet ignores where Include occurs, other Include paths, and whether directives are conditional. For example, an early Include containing `PasswordAuthentication yes` can be incorrectly overridden in the scan by a later main-file `no`. Plain `sshd -T` describes global defaults, not every Match-specific connection. The running daemon may use another config or command-line overrides; installed sshd also does not prove it is listening on the reported port.
**Suggested fix:** On failed effective-config inspection, mark the result incomplete instead of guessing from concatenated files. Use explicit representative `sshd -T -C` contexts where appropriate, explain coverage, and distinguish configured ports from observed listeners. Preserve command exit status before `tr`; inspect the actual service invocation when claiming runtime configuration.

### 7. HIGH — Failed probes become clean passes and a reassuring grade
**Lines 179–183, 356–363, 377–403, 494–512, 545–551, 659, 736–737.** Failed `ss`, package queries and `find` can produce empty output which is treated as success. Missing DNF cache can therefore become “No updates waiting”; unreadable directories can become “No world-writable files”. Pipelines discard producer status. Skipped checks do not lower confidence, so an incomplete scan can still declare “SECURE!” and exit zero.
**Suggested fix:** Capture stdout and exit status separately, recognise manager-specific success codes (DNF 100 means updates), and propagate errors as unknown/skipped. Track coverage independently of the score, remove the absolute security claim and define an incomplete-scan exit status. Do not simply enable `set -e` globally. [DNF exit codes](https://dnf.readthedocs.io/en/latest/command_ref.html).

### 8. HIGH, conditional — Root execution trusts executable configuration and command lookup
**Lines 1, 172–174, 196–201, throughout external commands.** Sourcing os-release executes shell code twice as root. The comment that a subshell stops anything “leaking” is misleading: file writes and connections still happen. A compromised os-release normally already implies privileged modification, so this is not an ordinary unprivileged escalation by itself. Inherited PATH/functions can similarly replace commands if the launch environment is untrusted; sudo often sanitises these, but direct root invocation need not.
**Suggested fix:** Parse the limited os-release assignment format as data without eval/source. Establish a trusted command environment and document launch assumptions; sanitisation inside the script cannot undo malicious BASH_ENV code already run by Bash. Avoid claiming safety against a fully compromised host.

### 9. MEDIUM — File traversal can trigger remote I/O; local reads can still change metadata
**Lines 240, 545, 575–586; all filesystem reads.** `find -xdev` is not a universal network guard: a starting directory can itself be remote, and automount lookup can trigger activity before descent is excluded. SSH snippets and certificate symlinks can lead to remote files or special files and block. Ordinary reads may update atime; audit/daemon activity can also write logs. Bash may use temporary files for sufficiently large here-documents/here-strings, including the ss input at line 356, depending on version and size.
**Suggested fix:** Define whether the promise means no deliberate configuration changes or literally no writes. For the latter, use enforced read-only local mounts, no automounts and restricted IPC/network access; skip paths that cannot be read safely. Add bounded execution and distinguish incomplete scans. `-xdev` alone cannot support the current comment.

### 10. MEDIUM — Listener classification hard-codes unsafe network assumptions
**Lines 176–183, 337–365, 472–477.** The ss columns are correctly selected for the two current invocations: field 4 for TCP-only `-tln`, field 5 with protocol for `-tuln`. The bug is classification: every `172.17.*` address is suppressed, although it can be a real routed LAN; VPN interface names generally are not attached to IPv4 addresses in ss output. IPv6 link-local, private LAN and VPN listeners are called public. A custom interface name can also match the exclusion patterns. Only the first configured SSH port is checked.
**Suggested fix:** Report “non-loopback listener”, show address/interface and protocol, and assess routing/firewall context separately. Do not silently suppress a subnet by convention. Check all observed SSH listeners, and keep failed enumeration distinct from no listeners.

### 11. MEDIUM — Update counting and advice are distribution/version fragile
**Lines 377–393, 457.** Zypper's `list-updates` table cannot reliably be counted using the search-style `^v ` status assumption; common output has repository/name/version columns without that marker. DNF's architecture allowlist misses supported architectures such as ppc64le/s390x and a regex over human output can count unrelated text. APT's `-security` substring is not authoritative security-origin identification, and missing/stale caches still yield weak conclusions. Tumbleweed normally needs a distribution upgrade rather than the generic `zypper update` advice.
**Suggested fix:** Use tested machine-readable manager output or local metadata with explicit status handling; use zypper XML if an appropriately isolated invocation is allowed. Count packages structurally, inspect origin metadata for security classification, show cache age/availability, and distinguish Leap from Tumbleweed for advice. Add stored output fixtures for each supported manager/version, including empty cache and error cases.

### 12. MEDIUM — Suggested firewall fixes can lock beginners out
**Lines 259, 262, 272, 306–311, 352.** `ufw allow OpenSSH` usually allows the profile's default port, not a custom SSH port. Enabling firewalld without first arranging the correct zone/port can also disconnect access. The SSH unit name varies (`ssh` on Debian/Ubuntu versus `sshd` elsewhere), and ufw advice is emitted even on systems using firewalld. These commands are only printed, not executed by the scan.
**Suggested fix:** Tailor instructions to the actual manager/unit and observed SSH ports; require checking the current access path, retaining the current session and testing a second connection. Explain distro-specific Include precedence before advising a main-file edit.

### 13. MEDIUM — Automatic-update and brute-force service presence overstates protection
**Lines 409–422, 466–477.** A commented APT setting can match; later overrides or disabled timers can invalidate it. A generic dnf-automatic timer may notify/download without applying updates. Fail2ban can run without an SSH jail; CrowdSec can run without a remediation component. Conversely a firewall or SSH authentication policy can block guessing without these services.
**Suggested fix:** Inspect effective local settings, scheduling and installation mode, and the relevant jail/remediation configuration. Otherwise report service presence only, without a protection pass or categorical “Nothing is blocking” claim. [DNF Automatic modes](https://dnf.readthedocs.io/en/stable/automatic.html).

### 14. MEDIUM — Docker socket check misses other world-writable modes and ACLs
**Lines 529–534.** Exact equality with `666` misses `667`, `676`, `777` and special-bit combinations; other-write access is what matters. An extended ACL can grant unexpected access. Failed stat also takes the pass branch.
**Suggested fix:** Validate stat success, test the other-write permission bit numerically, inspect ownership and ACLs, and qualify the result if ACL inspection is unavailable.

### 15. MEDIUM — Writable-system-file check misses directories and Arch's usr-merge paths
**Lines 545–551.** Writable directories allow replacement of files regardless of file mode; only regular files are checked. On Arch `/usr/sbin` is commonly a symlink and some other distributions use `/usr/bin` as a symlink too; find's default symlink handling can skip starting paths. Group/ACL write access is also outside this test.
**Suggested fix:** Resolve and deduplicate trusted starting paths without blindly following arbitrary child symlinks, check directory ownership/write permissions and relevant ACLs, and describe the actual coverage rather than a broad system-folder pass.

### 16. LOW — Account, clock, certificate and backup wording exceeds evidence
**Lines 487–500, 508–510, 559–564, 582–591, 605.** Group membership is not effective sudo policy and misses primary-group membership/direct sudoers grants. Empty shadow passwords do not always permit login (PAM and service policy matter). A failed timedatectl call is not evidence that synchronisation is disabled. Invalid/unreadable certificates are labelled expired, and checkend does not validate trust, hostname or notBefore. An installed backup tool proves no backup exists or succeeds.
**Suggested fix:** Report these as narrow observations, distinguish errors from negative results, and use informational/unknown outcomes where the effective policy or operation was not verified.

### 17. LOW — Untrusted display text can spoof terminal/report output
**Lines 198, 350, 494–510, 545–548, 581–591, 694.** Names/config text are generally quoted safely and are not re-evaluated as shell code. However filenames can contain newlines, terminal escapes and Markdown; newline-delimited find output loses filename boundaries and can make findings misleading. The deliberate glob over absolute certificate paths is not itself command injection.
**Suggested fix:** Escape control characters and Markdown in display/report fields; use NUL-delimited filename enumeration. Retain the existing array quoting. The unquoted seq expansion at line 668 is generated numeric data, not a demonstrated malicious-filename execution path.

## Missing beginner-relevant checks (five maximum)

These are additions, ranked after correcting the unsafe or misleading existing results; line references identify relevant insertion areas.

1. **Lines 481–517:** Local sudoers policy and dangerous privilege grants (NOPASSWD/ALL, writable policy files, unexpected direct users). Parse safely without remote NSS and clearly bound effective-policy claims.
2. **Lines 539–553:** Sensitive file ownership/readability: shadow, SSH private keys and privileged service/unit configuration, including parent-directory and ACL protection.
3. **Lines 193–211, 370–438:** Unsupported OS releases and stale/missing package metadata. Use a bundled, dated lifecycle table and state its age; never fetch data during a scan.
4. **Lines 539–553:** SELinux/AppArmor availability and enforcement state, with distro-aware informational guidance rather than penalising every absent mechanism.
5. **Lines 598–611:** Existing local backup schedule, last-success evidence and restore-test reminder. Do not execute backup tools or contact repositories to discover this; unknown is better than an installed-tool pass.

## Promise audit summary

No explicit download, install, chmod, passwd, reboot or service-changing command is executed by the main scan; those strings are advice. The exceptions/indirect paths above still defeat the absolute promise. `systemctl` and `timedatectl` query local service-manager IPC; timedatectl can activate its D-Bus service. `ss`, `nft` and `iptables` communicate with the local kernel, not remote hosts, though invoking tools/daemons is not a blanket guarantee against logs, locks or module-related side effects. `ufw status` also delegates inspection to its backend. Thus “no remote probing intended” is defensible; “NEVER changes anything and NEVER connects anywhere” is not established by this implementation.

For follow-up validation, use offline fixtures/mocks for parsing and disposable, network-isolated distribution environments with filesystem/syscall monitoring for side effects. Do not validate the no-change promise by simply running the scanner as root on a real host.
