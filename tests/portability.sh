#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
# Source definitions only; no host scan runs.
source ./franken-scan.sh
package_cache_available() { return 0; }
section() { :; }
info() { :; }
pass() { printf 'PASS %s\n' "$*"; }
skip() { printf 'SKIP %s\n' "$*"; }
problem() { printf 'PROBLEM %s\n' "$*"; }
have() { return 0; }
apt() { printf 'Listing...\n'; return 42; }
pacman() { return 42; }
FAMILY=debian
output=$(check_updates)
[[ "$output" == *'SKIP Pending updates'* ]]
[[ "$output" != *'PASS No updates waiting'* ]]
apt() { printf 'Listing...\npkg/stable 2 amd64 [upgradable from: 1]\n'; }
output=$(check_updates)
[[ "$output" == *'1 update(s) waiting'* ]]
FAMILY=arch
KERNEL=$(uname -r)
output=$(check_updates)
[[ "$output" == *'SKIP Pending updates'* ]]
pacman() { printf 'first\nsecond\n'; }
output=$(check_updates)
[[ "$output" == *'2 update(s) waiting'* ]]
pacman() { return 1; }
output=$(check_updates)
[[ "$output" == *'PASS No updates waiting'* ]]
pacman() { printf 'error: failed to initialise database\n' >&2; return 1; }
output=$(check_updates)
[[ "$output" == *'SKIP Pending updates'* ]]
FAMILY=suse
DISTRO_ID=opensuse-tumbleweed
[[ $(update_cmd) == 'sudo zypper dup' ]]
DISTRO_ID=opensuse-leap
[[ $(update_cmd) == 'sudo zypper update' ]]
# Exact-format parsing rejects garbage and deduplicates package architectures.
[[ $(printf 'one.x86_64\none.x86_64\ntwo.aarch64\n' | count_package_names) = 2 ]]
if printf 'warning: broken cache\n' | count_package_names; then exit 1; fi
[[ $(printf '<stream><update-status><update-list><update kind="package" name="one" arch="x86_64"/></update-list></update-status></stream>' | count_zypper_updates) = 1 ]]
[[ $(printf '<stream><update-status><update-list/></update-status></stream>' | count_zypper_updates) = 0 ]]
if printf '<stream><message>failed</message></stream>' | count_zypper_updates; then exit 1; fi
if printf '<broken' | count_zypper_updates 2>/dev/null; then exit 1; fi
# Missing cache must override otherwise successful empty queries.
package_cache_available() { return 1; }
FAMILY=debian
apt() { printf 'Listing...\n'; }
output=$(check_updates)
[[ "$output" == *'SKIP Pending updates'* ]]
# A failed listener enumeration is distinct from no listener.
ss() { return 42; }
if listening_publicly 22; then exit 1; else [[ $? = 2 ]]; fi
ss() { printf 'LISTEN 0 128 172.17.0.2:22 0.0.0.0:*\n'; }
listening_publicly 22
ss() { printf 'LISTEN 0 128 [::1]:22 [::]:*\n'; }
if listening_publicly 22; then exit 1; else [[ $? = 1 ]]; fi
# A failed namespace setup must never fall back to executing the query.
unshare() { return 1; }
if offline_query bash -c 'exit 0'; then exit 1; fi
printf 'Portability regression tests passed\n'
