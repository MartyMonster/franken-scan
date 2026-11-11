#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
# Source definitions only; no host scan runs.
source ./franken-scan.sh
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
pacman() { printf 'first 1 -> 2\nsecond 3 -> 4\n'; }
output=$(check_updates)
[[ "$output" == *'2 update(s) waiting'* ]]
FAMILY=suse
DISTRO_ID=opensuse-tumbleweed
[[ $(update_cmd) == 'sudo zypper dup' ]]
DISTRO_ID=opensuse-leap
[[ $(update_cmd) == 'sudo zypper update' ]]
printf 'Portability regression tests passed\n'
