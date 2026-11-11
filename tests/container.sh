#!/usr/bin/env bash
# Runs only inside a disposable test container, never on a user's host.
set -eu
cd /src
bash -n franken-scan.sh
bash tests/portability.sh
bash tests/detection.sh
find /etc -xdev -type f -exec sha256sum {} + | sort > /tmp/config-before.txt
for user in root nobody; do
  set +e
  if [ "$user" = root ]; then
    timeout 90 bash franken-scan.sh --no-color --report /tmp/report.md > /tmp/scan-root.txt 2>&1
  else
    setpriv --reuid=65534 --regid=65534 --clear-groups timeout 90 bash /src/franken-scan.sh --no-color > /tmp/scan-nobody.txt 2>&1
  fi
  rc=$?
  set -e
  cat "/tmp/scan-$user.txt"
  [[ $rc = 0 || $rc = 1 ]]
  grep -q '── Result ──' "/tmp/scan-$user.txt"
  grep -q 'Grade [ABCDF]' "/tmp/scan-$user.txt"
  if grep -Eq 'command not found|unbound variable|syntax error|Traceback' "/tmp/scan-$user.txt"; then exit 1; fi
done
[[ $(stat -c %a /tmp/report.md) = 600 ]]
# A second report request must preserve the existing report.
sha256sum /tmp/report.md > /tmp/report.checksum
bash franken-scan.sh --no-color --report /tmp/report.md >/tmp/repeat.txt || [[ $? = 1 ]]
sha256sum -c /tmp/report.checksum
printf 'keep me\n' >/tmp/target
ln -s /tmp/target /tmp/link
bash franken-scan.sh --no-color --report /tmp/link >/tmp/symlink.txt || [[ $? = 1 ]]
[[ $(cat /tmp/target) = 'keep me' ]]
find /etc -xdev -type f -exec sha256sum {} + | sort > /tmp/config-after.txt
diff -u /tmp/config-before.txt /tmp/config-after.txt
printf 'Container scan and report-safety tests passed\n'
