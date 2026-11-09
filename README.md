# franken-scan 🧟

> **It's alive!… but is it secure?**

A friendly, **read-only** security check-up for Linux servers and PCs. It tells you what's wrong in
plain English, why it matters, and the exact command to fix it. Then it gives your box a grade from
A to F, and a monster whose eye gets more bloodshot the worse things are.

```
── SSH (remote login) ──
  ✗ [HIGH] SSH accepts passwords
      Why: Passwords can be guessed by bots. SSH keys can't. (Make sure your key login works BEFORE turning passwords off!)
      Fix: Set 'PasswordAuthentication no' in /etc/ssh/sshd_config, then: sudo systemctl reload sshd

── Firewall ──
  ✓ A firewall is active: ufw

    \             /
     \  _______  /
      |/  ___  \|
      | ( ~o  ) |
    =[|   >_    |]=
      |  ~~~~~  |
      \_|_|_|_|_/
  Not bad. A few stitches to tighten.

  Grade: B  (score 87/100)
```

## The promise

- **It only looks.** It never changes anything on your system.
- **No network.** It doesn't connect anywhere, send anything or phone home.
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

Exit code is `0` when there are no HIGH problems and `1` when there's at least one, so you can use it in scripts and cron.

## What it checks

| Area | Checks |
|---|---|
| **SSH** | root login, password logins, port |
| **Firewall** | ufw, firewalld, nftables or iptables actually active |
| **Open ports** | anything listening publicly, with databases, Docker API, RDP, VNC, SMB, FTP and Telnet flagged as HIGH |
| **Updates** | pending updates (from the local cache, no network), automatic security updates, reboot needed |
| **Brute-force** | fail2ban, CrowdSec or sshguard running when SSH is public |
| **Accounts** | who has sudo, hidden UID-0 accounts, empty passwords |
| **Docker** | socket permissions, docker-group members |
| **System files** | world-writable files in system folders |
| **Clock** | time sync |
| **HTTPS** | Let's Encrypt certificates expired or expiring within 14 days |
| **Backups** | any backup tool present (restic, borg, timeshift…) |

**Scoring:** you start at 100. HIGH costs 20, MEDIUM 10, LOW 3.
A ≥ 90 · B ≥ 75 · C ≥ 60 · D ≥ 40 · F below that.

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
