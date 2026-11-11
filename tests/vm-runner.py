"""Boot a cloud image in an unprivileged QEMU process, with isolated user networking."""
import base64
import json
import pathlib
import subprocess
import sys
import time

root = pathlib.Path.cwd()
work = pathlib.Path(sys.argv[1]).resolve()
work.mkdir(parents=True, exist_ok=True)
files = []
for name in ['franken-scan.sh', 'tests/vm-guest.sh']:
    files.append({'path': '/opt/franken-scan/' + name,
                  'encoding': 'b64', 'permissions': '0755',
                  'content': base64.b64encode((root / name).read_bytes()).decode()})
config = {'write_files': files,
          'runcmd': [['bash', '-c', 'bash /opt/franken-scan/tests/vm-guest.sh > /dev/ttyS0 2>&1; poweroff']],
          'ssh_pwauth': False, 'disable_root': True,
          'package_update': False, 'package_upgrade': False}
(work / 'user-data').write_text('#cloud-config\n' + json.dumps(config))
(work / 'meta-data').write_text('instance-id: franken-ci\nlocal-hostname: franken-ci\n')
subprocess.run(['cloud-localds', str(work / 'seed.img'), str(work / 'user-data'), str(work / 'meta-data')], check=True)
subprocess.run(['qemu-img', 'create', '-f', 'qcow2', '-F', 'qcow2', '-b', str(work / 'base.qcow2'), str(work / 'disk.qcow2')], check=True)
cmd = ['qemu-system-x86_64', '-machine', 'q35,accel=tcg', '-cpu', 'max', '-m', '2048', '-smp', '2',
       '-display', 'none', '-serial', 'file:' + str(work / 'serial.log'), '-no-reboot',
       '-drive', 'file=' + str(work / 'disk.qcow2') + ',if=virtio,format=qcow2',
       '-drive', 'file=' + str(work / 'seed.img') + ',if=virtio,format=raw',
       '-netdev', 'user,id=n0,restrict=on', '-device', 'virtio-net-pci,netdev=n0']
# UEFI is supported by all three chosen images.
cmd += ['-drive', 'if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd']
with subprocess.Popen(cmd) as proc:
    deadline = time.monotonic() + 600
    try:
        while proc.poll() is None and time.monotonic() < deadline:
            time.sleep(2)
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=15)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
log = (work / 'serial.log').read_text(errors='replace')
print(log)
if 'FRANKEN_VM_PASS' not in log:
    sys.exit('VM integration test did not reach its success marker')
