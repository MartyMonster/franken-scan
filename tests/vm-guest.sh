#!/usr/bin/env bash
set -eu
cd /opt/franken-scan
# Cloud images have systemd and SSH installed. No packages are installed here.
bash -c 'source ./franken-scan.sh; systemd_running; detect_system /etc/os-release; svc_active "$(ssh_service)"'
set +e
timeout 90 bash franken-scan.sh --no-color --report /tmp/vm-report.md > /tmp/vm-scan.txt 2>&1
rc=$?
set -e
cat /tmp/vm-scan.txt
[[ $rc = 0 || $rc = 1 ]]
grep -q 'SSH is set to use port' /tmp/vm-scan.txt
grep -q '── Result ──' /tmp/vm-scan.txt
if grep -Eq 'command not found|unbound variable|syntax error|Traceback' /tmp/vm-scan.txt; then exit 1; fi
printf '\nFRANKEN_VM_PASS\n'
