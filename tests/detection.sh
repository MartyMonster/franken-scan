#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
source ./franken-scan.sh
fixture=$(mktemp)
trap 'rm -f "$fixture"' EXIT
for spec in 'debian:debian' 'ubuntu:debian' 'arch:arch' 'fedora:fedora' 'opensuse-leap:suse' 'opensuse-tumbleweed:suse' 'unknown:other'; do
  printf 'ID=%s\nNAME="Fixture"\n' "${spec%:*}" > "$fixture"
  detect_system "$fixture"
  [[ "$FAMILY" = "${spec#*:}" ]]
done
for spec in 'rocky:rhel:fedora' 'almalinux:rhel:fedora' 'omarchy:arch:arch' 'manjaro:arch:arch' 'mint:ubuntu:debian'; do
  IFS=: read -r distro like expected <<< "$spec"
  printf 'ID=%s\nID_LIKE="%s"\n' "$distro" "$like" > "$fixture"
  detect_system "$fixture"
  [[ "$FAMILY" = "$expected" ]]
done
# Shell syntax in os-release is data, never evaluated.
printf 'ID=unknown\nPRETTY_NAME="$(exit 99)"\n' > "$fixture"
detect_system "$fixture"
[[ "$DISTRO_NAME" = '$(exit 99)' ]]
printf 'Distro detection fixtures passed\n'
