# franken-scan 🧟

```
       .-----------------------.
      / .---------------------. \
     | |                       | |
     | |   _   _   _   _   _   | |
     | |  | |_| |_| |_| |_| |  | |
     |_|__|_________________|__|_|
     |                           |
     |     =====       =====     |
     |      (o)         (o)      |
     |            / \            |
     |           /___\           |
 ____|                           |____
|    |       _____________       |    |
|    |=======|_|_|_|_|_|_|=======|    |
|____|                           |____|
     |   --+---+---+---+---+--   |
      \                         /
       \_______________________/
```

> **It's alive!… but is it secure?**

A friendly, **read-only** security check-up for Linux servers and PCs. It tells you what's wrong in
plain English, why it matters, and the exact command to fix it (for *your* distro), then gives
your box a grade from A to F.

```
    ____                 __
   / __/________ _____  / /_____  ____        ______________ _____
  / /_/ ___/ __ `/ __ \/ //_/ _ \/ __ \______/ ___/ ___/ __ `/ __ \
 / __/ /  / /_/ / / / / ,< /  __/ / / /_____(__  ) /__/ /_/ / / / /
/_/ /_/   \__,_/_/ /_/_/|_|\___/_/ /_/     /____/\___/\__,_/_/ /_/
  v1.0.1 · It's alive!… but is it secure?

── SSH (remote login) ──
  ✗ [HIGH] SSH accepts passwords
    Why: Passwords can be guessed by bots. SSH keys can't. (Make sure your key
         login works BEFORE turning passwords off, and keep your current
         session open while you test!)
    Fix: Set 'PasswordAuthentication no': add it to a new file
         /etc/ssh/sshd_config.d/00-hardening.conf, then: sudo sshd -t && sudo
         systemctl reload ssh

── Firewall ──
  ✓ ufw is on and blocks incoming connections by default

── Result ──
  Grade B · 80/100 · Not bad. A few stitches to tighten.
  9 passed · 1 high · 0 medium · 0 low · 0 skipped
```

## The promise

- **It only looks.** It never changes your configuration: no installs, no edits, no restarts.
  *(Small print, because honesty matters: package tools it asks, like dnf or zypper, may write
  to their own logs, and reading files can update their "last accessed" time.)*
- **It never contacts the internet.** Nothing is sent anywhere, no telemetry, no phoning home.
  (It reads local files directly rather than asking LDAP/AD servers about users and groups.)
- **The only file it creates** is the report, and only with `--report`. It refuses to overwrite
  anything that already exists, including symlinks.
- **One file, nothing to install.** Just bash and the standard tools already on your system.
- **Read it yourself.** It's one commented script. Please do read it before running it with sudo,
  because that's a good habit with *any* script from the internet.

## Run it

```bash
# 1. Download the latest release
curl -fsSLO https://github.com/MartyMonster/franken-scan/releases/latest/download/franken-scan.sh
curl -fsSLO https://github.com/MartyMonster/franken-scan/releases/latest/download/franken-scan.sh.sha256

# 2. Check it arrived intact
sha256sum -c franken-scan.sh.sha256

# 3. Have a read (seriously, it's short and commented)
less franken-scan.sh

# 4. Run it
bash franken-scan.sh          # quick look as your normal user
sudo bash franken-scan.sh     # the full scan
```

> You'll notice there's no `curl … | sudo bash` one-liner. That's on purpose: piping internet scripts
> straight into a root shell is exactly the kind of habit a security tool shouldn't teach.

### Options

| Option | What it does |
|---|---|
| `--report [FILE]` | Also saves a Markdown report you can keep or hand to whoever looks after the server |
| `--quiet` | Only shows problems |
| `--no-color` | Plain output |
| `--version` / `--help` | What you'd expect |
| `--monster` | Says hello. That's it. |

Exit code is `0` when there are no HIGH problems and `1` when there's at least one, so you can use it in scripts and cron.

## What it checks

| Area | Checks |
|---|---|
| **SSH** | effective settings via `sshd -T`: password logins (including the sneaky keyboard-interactive/PAM route), root login, ports |
| **Firewall** | actually *blocking* incoming traffic, not just running (ufw default policy, firewalld zone, nftables/iptables policy) |
| **Open ports** | anything listening publicly, with databases, Docker API, RDP, VNC, SMB, FTP and Telnet flagged as HIGH |
| **Updates** | pending updates (from the local cache, no network), automatic security updates, reboot needed |
| **Brute-force** | fail2ban (with an SSH jail), CrowdSec or sshguard, when SSH is public |
| **Accounts** | who has sudo, hidden UID-0 accounts, empty passwords |
| **Docker** | socket permissions, docker-group members |
| **System files** | world-writable files in system folders |
| **Clock** | time sync |
| **HTTPS** | Let's Encrypt certificates expired or expiring within 14 days |
| **Backups** | any backup tool present (restic, borg, timeshift…) |

**Scoring:** you start at 100. HIGH costs 20, MEDIUM 10, LOW 3.
A ≥ 90 · B ≥ 75 · C ≥ 60 · D ≥ 40 · F below that.
If anything was skipped (usually because it wasn't run with sudo), the result says the scan was
**incomplete**: a check that couldn't run is never counted as a pass.

## Works on

Debian, Ubuntu, Arch (and Omarchy, Manjaro…), Fedora, RHEL, Rocky, Alma and openSUSE, on x86_64
and ARM (Raspberry Pi, RockPi and friends). It's tested on Debian 12, Ubuntu 24.04, Fedora 41,
Rocky 9 and Arch.

## Found problems you'd rather not fix yourself?

That's literally my job. I do Linux server setup and hardening for small businesses:
**[martymonster.dev](https://martymonster.dev/services#linux)**

## Contributing

Issues and pull requests are welcome. Keep the promise intact (read-only, no network, one file),
and run `shellcheck franken-scan.sh` before sending changes.

## Licence

MIT. See [LICENSE](LICENSE). Made by Martin Petkovski ([MartyMonster](https://martymonster.dev)).
