#!/usr/bin/env bash
#
#  franken-scan: "It's alive!… but is it secure?"
#
#  A quick, friendly security check-up for Linux boxes. I wrote it because the
#  big audit tools are brilliant but spit out hundreds of lines of jargon, and
#  most people running a VPS or a home server just want to know two things:
#  "am I OK?" and "what do I fix?". So that's all this does.
#
#  Ground rules I'm sticking to (read the code and hold me to them):
#    - it only LOOKS. It never changes a thing on your system.
#    - it never touches the network or phones home. No telemetry, nothing.
#    - it's one bash file with nothing to install.
#
#  Run it:
#    bash franken-scan.sh          # quick look as your normal user
#    sudo bash franken-scan.sh     # the full scan (some files need root to read)
#
#  Martin (MartyMonster), https://martymonster.dev
#  SPDX-License-Identifier: MIT   (full text in the LICENSE file)
#

# Blow up on typos in variable names. I'm NOT using "set -e" on purpose:
# half these checks run commands that "fail" as a perfectly normal answer.
set -u

# Force plain English output from every tool, so the text matching below
# works the same no matter what language your system is set to.
export LC_ALL=C

VERSION="1.0.0"


# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

USE_COLOR=1
QUIET=0
REPORT_FILE=""

# Everyone starts on 100 and loses points per problem. HIGH hurts the most
# because those are the ones that actually get servers popped.
PENALTY_HIGH=20
PENALTY_MED=10
PENALTY_LOW=3

show_help() {
  cat <<'EOF'
franken-scan: a friendly, read-only security check-up for Linux.

Usage: bash franken-scan.sh [options]

  --report [FILE]   also save a Markdown report
                    (default: franken-scan-report-<hostname>-<date>.md)
  --quiet           only show problems
  --no-color        no colours
  --version         print the version
  -h, --help        this help

Tip: run with sudo for the full scan. Without it, a few checks get skipped
(you'll see which ones). franken-scan never changes your system and never
uses the network.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --report)
      # --report on its own picks a sensible file name. If the next word
      # isn't another option, treat it as the file name instead.
      if [ $# -gt 1 ] && [ "${2#--}" = "$2" ]; then
        REPORT_FILE="$2"; shift
      else
        REPORT_FILE="franken-scan-report-$(hostname 2>/dev/null || echo host)-$(date +%Y-%m-%d).md"
      fi ;;
    --quiet)    QUIET=1 ;;
    --no-color) USE_COLOR=0 ;;
    --version)  echo "franken-scan $VERSION"; exit 0 ;;
    -h|--help)  show_help; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# Piping into a file or another command? Then colour codes would just be junk.
# Also respect the NO_COLOR convention (https://no-color.org).
if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then USE_COLOR=0; fi


# ---------------------------------------------------------------------------
# Printing stuff
# ---------------------------------------------------------------------------

if [ "$USE_COLOR" -eq 1 ]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'; C_GREY=$'\e[90m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_GREY=""
fi

SCORE=100
COUNT_PASS=0; COUNT_HIGH=0; COUNT_MED=0; COUNT_LOW=0; COUNT_SKIP=0

# Everything we print also gets stashed here as Markdown, so --report can
# dump the lot into a file at the end without running the checks twice.
REPORT_LINES=()

section() {
  printf '\n%s── %s ──%s\n' "$C_BOLD$C_BLUE" "$1" "$C_RESET"
  REPORT_LINES+=("" "## $1" "")
}

pass() {
  COUNT_PASS=$((COUNT_PASS + 1))
  [ "$QUIET" -eq 1 ] || printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"
  REPORT_LINES+=("- ✅ $1")
}

# problem <high|medium|low> "what's wrong" "why you should care" "how to fix it"
#
# The "why" matters as much as the "what". People fix things when they
# understand the risk, and ignore warnings when they don't.
problem() {
  local sev="$1" title="$2" why="$3" fix="${4:-}" colour label
  case "$sev" in
    high)   SCORE=$((SCORE - PENALTY_HIGH)); COUNT_HIGH=$((COUNT_HIGH + 1)); colour="$C_RED";    label="HIGH" ;;
    medium) SCORE=$((SCORE - PENALTY_MED));  COUNT_MED=$((COUNT_MED + 1));   colour="$C_YELLOW"; label="MEDIUM" ;;
    *)      SCORE=$((SCORE - PENALTY_LOW));  COUNT_LOW=$((COUNT_LOW + 1));   colour="$C_YELLOW"; label="LOW" ;;
  esac
  printf '  %s✗ [%s]%s %s\n' "$colour" "$label" "$C_RESET" "$title"
  printf '      %sWhy:%s %s\n' "$C_DIM" "$C_RESET" "$why"
  [ -n "$fix" ] && printf '      %sFix:%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD" "$fix" "$C_RESET"
  REPORT_LINES+=("- ❌ **[$label] $title**" "  - Why: $why")
  [ -n "$fix" ] && REPORT_LINES+=("  - Fix: \`$fix\`")
}

# Worth knowing, but not something you get marked down for.
info() {
  [ "$QUIET" -eq 1 ] || printf '  %si%s %s\n' "$C_BLUE" "$C_RESET" "$1"
  REPORT_LINES+=("- ℹ️ $1")
}

# Couldn't check it. I'd rather say so honestly than quietly pretend it passed.
skip() {
  COUNT_SKIP=$((COUNT_SKIP + 1))
  [ "$QUIET" -eq 1 ] || printf '  %s- skipped: %s%s\n' "$C_GREY" "$1" "$C_RESET"
  REPORT_LINES+=("- ⏭️ Skipped: $1")
}

have()       { command -v "$1" >/dev/null 2>&1; }
is_root()    { [ "$(id -u)" -eq 0 ]; }
svc_active() { have systemctl && systemctl is-active --quiet "$1" 2>/dev/null; }

# Is something listening on this port on a NON-local address?
# (Loopback, VPN-only and Docker-bridge addresses don't count as "public".)
listening_publicly() {
  have ss || return 1
  ss -H -tln 2>/dev/null | awk '{print $4}' | while read -r a; do
    case "$a" in 127.*|"[::1]"*|*%lo:*|*%tailscale*|*%wg*|*%docker*|172.17.*) continue ;; esac
    [ "${a##*:}" = "$1" ] && echo yes && break
  done | grep -q yes
}


# ---------------------------------------------------------------------------
# What are we running on?
# ---------------------------------------------------------------------------

# Different distros, different package managers. FAMILY decides which update
# commands we look at and which fix commands we suggest.
detect_system() {
  DISTRO_NAME="Unknown Linux"; FAMILY="other"
  if [ -r /etc/os-release ]; then
    # Sourced inside $( ) so nothing in that file can leak into our script.
    # shellcheck disable=SC1091
    DISTRO_NAME=$(. /etc/os-release && echo "${PRETTY_NAME:-$NAME}")
    local ids
    # shellcheck disable=SC1091
    ids=$(. /etc/os-release && echo "${ID:-} ${ID_LIKE:-}")
    case " $ids " in
      *" debian "*|*" ubuntu "*)            FAMILY="debian" ;;
      *" arch "*)                           FAMILY="arch" ;;
      *" fedora "*|*" rhel "*|*" centos "*) FAMILY="fedora" ;;   # also Rocky, Alma etc.
      *" suse "*|*" opensuse "*)            FAMILY="suse" ;;
    esac
  fi
  ARCH=$(uname -m)       # x86_64, aarch64 (Pi / RockPi boards), etc.
  KERNEL=$(uname -r)
}


# ---------------------------------------------------------------------------
# The checks. One function each, and every one of them only READS.
# ---------------------------------------------------------------------------

# SSH first, because it's the front door and the bots know it.
check_ssh() {
  section "SSH (remote login)"

  if ! have sshd && [ ! -e /usr/sbin/sshd ]; then
    info "No SSH server installed, so nothing to check here."
    return
  fi
  local sshd_bin; sshd_bin=$(command -v sshd || echo /usr/sbin/sshd)

  # "sshd -T" gives the REAL settings after all the includes and defaults are
  # applied, but it needs root. Without root we read the config files
  # ourselves, which is close enough for a quick look.
  # Everything gets lower-cased: older OpenSSH prints "passwordauthentication",
  # newer ones print "PasswordAuthentication". (That one caught me out. The
  # script happily told me my keys-only box accepted passwords.)
  local cfg=""
  if is_root; then
    cfg=$("$sshd_bin" -T 2>/dev/null | tr '[:upper:]' '[:lower:]')
  fi
  if [ -z "$cfg" ]; then
    if [ -r /etc/ssh/sshd_config ]; then
      cfg=$(cat /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null \
            | sed 's/#.*//' | tr '[:upper:]' '[:lower:]' | awk 'NF>=2 {print $1, $2}')
      info "Read SSH settings from the config file (run with sudo for exact results)."
    else
      skip "SSH settings (can't read /etc/ssh/sshd_config, try sudo)"
      return
    fi
  fi

  # sshd uses the FIRST value it finds for a setting, so we do too.
  ssh_opt() { printf '%s\n' "$cfg" | awk -v k="$1" '$1==k {print $2; exit}'; }

  # No setting at all means the modern default: root can log in with a key only.
  local root_login; root_login=$(ssh_opt permitrootlogin)
  case "${root_login:-prohibit-password}" in
    no) pass "Root can't log in over SSH" ;;
    prohibit-password|without-password)
        problem low "Root can log in over SSH with a key" \
          "Logging in as a normal user and using sudo leaves a clearer trail and limits the damage if a key leaks." \
          "Set 'PermitRootLogin no' in /etc/ssh/sshd_config, then: sudo systemctl reload sshd" ;;
    *)  problem high "Root can log in over SSH with a password" \
          "Bots try root passwords against every server on the internet, all day, every day." \
          "Set 'PermitRootLogin no' in /etc/ssh/sshd_config, then: sudo systemctl reload sshd" ;;
  esac

  local pw; pw=$(ssh_opt passwordauthentication)
  if [ "${pw:-yes}" = "no" ]; then
    pass "SSH only accepts keys, not passwords"
  else
    # The bit in brackets has saved more than one person from locking themselves out.
    problem high "SSH accepts passwords" \
      "Passwords can be guessed by bots. SSH keys can't. (Make sure your key login works BEFORE turning passwords off!)" \
      "Set 'PasswordAuthentication no' in /etc/ssh/sshd_config, then: sudo systemctl reload sshd"
  fi

  # Moving SSH off port 22 cuts down log spam but isn't real security,
  # so it's just mentioned, not scored.
  SSH_PORT=$(ssh_opt port); SSH_PORT=${SSH_PORT:-22}
  info "SSH listens on port $SSH_PORT."
}

check_firewall() {
  section "Firewall"
  local found=""

  # Try the usual suspects, most specific first. Reading the actual rules
  # needs root; without it we settle for "is a firewall service running?".
  if have ufw && is_root && ufw status 2>/dev/null | grep -q "Status: active"; then
    found="ufw"
  elif svc_active firewalld; then
    found="firewalld"
  elif is_root && have nft && nft list ruleset 2>/dev/null | grep -qE "hook input.*policy (drop|reject)|^[[:space:]]*(tcp|udp|ct|iif|ip) "; then
    found="nftables"
  elif is_root && have iptables && iptables -S INPUT 2>/dev/null | grep -qE "^-P INPUT (DROP|REJECT)|^-A INPUT"; then
    found="iptables"
  elif svc_active ufw; then
    found="ufw (service running)"
  elif svc_active nftables; then
    found="nftables (service running)"
  fi

  if [ -n "$found" ]; then
    pass "A firewall is active: $found"
  elif ! is_root; then
    skip "Firewall rules (need sudo to read them; no firewall service seen running)"
  else
    problem high "No active firewall found" \
      "Without a firewall, every service you run is reachable from the internet, including the ones you forgot about." \
      "Debian/Ubuntu: sudo ufw allow OpenSSH && sudo ufw enable   ·   Fedora/RHEL: sudo systemctl enable --now firewalld"
  fi
}

check_ports() {
  section "Open ports"
  if ! have ss; then skip "Open ports (the 'ss' tool isn't installed)"; return; fi

  # The "please don't put these on the internet" list. Every one of these
  # gets hit by mass scanners within minutes of going online.
  declare -A RISKY=(
    [21]="FTP (sends passwords in plain text)"     [23]="Telnet (sends everything in plain text)"
    [139]="Windows file sharing (SMB)"              [445]="Windows file sharing (SMB)"
    [2375]="Docker API with NO encryption (that's full control of the box)"
    [2376]="Docker API"                              [3306]="MySQL/MariaDB database"
    [3389]="Remote Desktop (RDP)"                    [5432]="PostgreSQL database"
    [5900]="VNC remote desktop"                      [6379]="Redis database"
    [9200]="Elasticsearch"                           [11211]="Memcached"
    [27017]="MongoDB database"
  )

  local others=() seen=" "
  while read -r proto _ _ _ local_addr _; do
    [ -z "${local_addr:-}" ] && continue
    local addr="${local_addr%:*}" port="${local_addr##*:}"

    # Only this machine (loopback), only over a VPN (Tailscale/WireGuard), or
    # only reachable by Docker containers. None of those are "on the internet".
    case "$addr" in 127.*|"[::1]"|*%lo|*%tailscale*|*%wg*|*%docker*|172.17.*) continue ;; esac

    # IPv4 and IPv6 usually both show up for the same port. Only report it once.
    case "$seen" in *" $port/$proto "*) continue ;; esac
    seen="$seen$port/$proto "

    if [ -n "${RISKY[$port]:-}" ]; then
      problem high "Port $port/$proto is open to the network: ${RISKY[$port]}" \
        "Databases and remote desktops are top targets for automated attacks. Keep them on 127.0.0.1 or behind a firewall/VPN." \
        "Bind the service to 127.0.0.1 in its config, or block it: sudo ufw deny $port"
    else
      others+=("$port/$proto")
    fi
  done <<< "$(ss -H -tuln 2>/dev/null)"

  # The rest go on one line. Listing each separately just buries the stuff
  # that matters (I learned that the first time I ran this on my own PC).
  if [ ${#others[@]} -gt 0 ]; then
    info "Also listening publicly: ${others[*]}. Make sure you meant each of these to be reachable."
  elif [ "$seen" = " " ]; then
    pass "Nothing is listening on public network addresses"
  fi
  info "(A firewall may still block some of these. This shows what's LISTENING, not what's reachable from outside.)"
}

# Everything here works off what's already on the machine: no "apt update",
# no network. So "no updates" really means "none as of your last refresh".
check_updates() {
  section "Updates"
  local pending=""

  case "$FAMILY" in
    debian)
      if have apt; then
        pending=$(apt list --upgradable 2>/dev/null | grep -c "upgradable from")
        # Security updates get called out on their own. They're the ones that matter most.
        local sec; sec=$(apt list --upgradable 2>/dev/null | grep -c -- "-security")
        if [ "$sec" -gt 0 ]; then
          problem medium "$sec security update(s) waiting" \
            "Security updates fix holes that attackers already know about." \
            "sudo apt update && sudo apt upgrade"
        fi
      fi ;;
    arch)
      # Compares against the local package database. Doesn't sync anything.
      have pacman && pending=$(pacman -Qu 2>/dev/null | wc -l) ;;
    fedora)
      # -C = cache only, so dnf won't go off and download metadata.
      have dnf && pending=$(dnf -C -q check-update 2>/dev/null | grep -cE '^[[:alnum:]].*\.(x86_64|aarch64|noarch|i686|armv7hl)') ;;
    suse)
      have zypper && pending=$(zypper --no-refresh -q list-updates 2>/dev/null | grep -c '^v ') ;;
  esac

  if [ -z "$pending" ]; then
    skip "Pending updates (don't know this package manager)"
  elif [ "$pending" -gt 0 ]; then
    problem medium "$pending update(s) waiting to be installed" \
      "Old software is the easy way in. Most attacks use holes that were patched months ago." \
      "$(update_cmd)"
  else
    pass "No updates waiting (as of the last time the package list was refreshed)"
  fi

  # Servers get forgotten. Automatic security updates are the safety net.
  case "$FAMILY" in
    debian)
      if grep -qs 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades; then
        pass "Automatic security updates are on"
      else
        problem medium "Automatic security updates are off" \
          "Servers get forgotten. Automatic security updates patch holes even when you don't." \
          "sudo apt install unattended-upgrades && sudo dpkg-reconfigure -plow unattended-upgrades"
      fi ;;
    fedora)
      if svc_active dnf-automatic.timer || svc_active dnf-automatic-install.timer || svc_active dnf5-automatic.timer; then
        pass "Automatic updates are on (dnf-automatic)"
      else
        problem medium "Automatic updates are off" \
          "Servers get forgotten. Automatic updates patch holes even when you don't." \
          "sudo dnf install dnf-automatic && sudo systemctl enable --now dnf-automatic.timer"
      fi ;;
    arch)
      # Not marking Arch down for this. Unattended updates on a rolling
      # distro is how you wake up to a broken system.
      info "Arch is a rolling release: update by hand regularly (automatic updates aren't recommended on Arch)." ;;
  esac

  # A patched kernel does nothing until you reboot into it.
  # Debian/Ubuntu leave a flag file. On Arch the old kernel's modules folder
  # disappears after an upgrade, which is a handy tell.
  if [ -e /var/run/reboot-required ] || { [ "$FAMILY" = "arch" ] && [ ! -d "/usr/lib/modules/$KERNEL" ]; }; then
    problem low "A reboot is needed to finish updates" \
      "Security fixes in the kernel only take effect after a reboot." \
      "sudo reboot   (when it suits you)"
  fi
}

update_cmd() {
  case "$FAMILY" in
    debian) echo "sudo apt update && sudo apt upgrade" ;;
    arch)   echo "sudo pacman -Syu" ;;
    fedora) echo "sudo dnf upgrade" ;;
    suse)   echo "sudo zypper update" ;;
    *)      echo "Update with your system's package manager" ;;
  esac
}

# Only really matters if SSH is open to the world. If it's not, no need to nag.
check_bruteforce() {
  section "Brute-force protection"
  local tool="" t
  for t in fail2ban crowdsec sshguard; do
    if svc_active "$t"; then tool="$t"; break; fi
  done

  if [ -n "$tool" ]; then
    pass "$tool is running (it bans IPs after repeated failed logins)"
  elif listening_publicly "${SSH_PORT:-22}"; then
    problem medium "Nothing is blocking repeated login attempts" \
      "Bots hammer SSH with guesses around the clock. fail2ban or CrowdSec bans them after a few failures." \
      "Debian/Ubuntu: sudo apt install fail2ban   ·   Fedora: sudo dnf install fail2ban && sudo systemctl enable --now fail2ban   ·   Arch: sudo pacman -S fail2ban && sudo systemctl enable --now fail2ban"
  else
    info "No brute-force protection running, but SSH isn't open publicly, so that's fine."
  fi
}

check_accounts() {
  section "User accounts"

  # Not a problem by itself. It's just a good moment to ask "should all of
  # these people still have the keys to the kingdom?"
  local admins
  admins=$(for g in sudo wheel admin; do getent group "$g" 2>/dev/null | cut -d: -f4; done \
           | tr ',' '\n' | grep -v '^$' | sort -u | paste -sd ' ' -)
  info "Users with admin (sudo) rights: ${admins:-none found}. Remove anyone who shouldn't be there."

  # UID 0 IS root, whatever the account is called. A second one is a classic
  # backdoor, so this one's worth checking even though it's rare.
  local uid0
  uid0=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd | paste -sd ' ' -)
  if [ -n "$uid0" ]; then
    problem high "Account(s) with full root powers besides root: $uid0" \
      "Hidden UID-0 accounts are a classic backdoor left behind by attackers." \
      "Look into these accounts in /etc/passwd straight away."
  else
    pass "Only 'root' has root powers (UID 0)"
  fi

  # Empty password = log in with no password. Needs root to read /etc/shadow.
  if [ -r /etc/shadow ]; then
    local empty
    empty=$(awk -F: '$2 == "" {print $1}' /etc/shadow | paste -sd ' ' -)
    if [ -n "$empty" ]; then
      problem high "Account(s) with an empty password: $empty" \
        "Anyone can log in as these users without a password." \
        "Lock them: sudo passwd -l USERNAME"
    else
      pass "No accounts have an empty password"
    fi
  else
    skip "Empty passwords (need sudo to read /etc/shadow)"
  fi
}

# Docker's handy but it's root in disguise. Skip the whole section if it's not installed.
check_docker() {
  [ -S /var/run/docker.sock ] || return
  section "Docker"

  # Anyone in the docker group can mount / into a container and do as they
  # please. Worth knowing who's in there.
  local members; members=$(getent group docker 2>/dev/null | cut -d: -f4)
  [ -n "$members" ] && info "Users in the 'docker' group (effectively root access): $members"

  if [ "$(stat -c '%a' /var/run/docker.sock 2>/dev/null)" = "666" ]; then
    problem high "Docker socket is open to every user" \
      "Anyone on this machine can control Docker, and through it become root." \
      "sudo chmod 660 /var/run/docker.sock   (then find out what changed it)"
  else
    pass "Docker socket permissions are restricted"
  fi
  # Docker exposed on the NETWORK (ports 2375/2376) gets caught in the ports check.
}

check_files() {
  section "System files"
  # Anything in these folders that ANY user can edit is a way to escalate to
  # root. -xdev keeps find on this one disk so it doesn't wander into network
  # mounts. Capped at 10 results so a really broken box doesn't flood the screen.
  local ww
  ww=$(find /etc /usr/bin /usr/sbin /usr/lib/systemd -xdev -type f -perm -0002 2>/dev/null | head -n 10 | paste -sd ' ' -)
  if [ -n "$ww" ]; then
    problem medium "System files that ANY user can edit" \
      "Someone with any account could change these to take over the system. Found: $ww" \
      "Remove 'anyone can write': sudo chmod o-w FILE"
  else
    pass "No world-writable files in system folders"
  fi
}

check_time() {
  section "Clock"
  # Sounds boring, but a drifting clock breaks HTTPS, 2FA codes and log timelines.
  if have timedatectl; then
    if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ]; then
      pass "Clock is synced automatically"
    else
      problem low "Clock isn't being synced" \
        "Logs, certificates and 2-factor codes all rely on the correct time." \
        "sudo timedatectl set-ntp true"
    fi
  else
    skip "Clock sync (timedatectl not available)"
  fi
}

# Only Let's Encrypt certs for now. That covers most small servers. If
# there aren't any (or we can't read them) this section stays out of the way.
check_tls() {
  local certs=() f
  for f in /etc/letsencrypt/live/*/cert.pem; do [ -r "$f" ] && certs+=("$f"); done
  [ ${#certs[@]} -eq 0 ] && return
  section "HTTPS certificates"
  if ! have openssl; then skip "Certificate expiry (openssl not installed)"; return; fi

  for f in "${certs[@]}"; do
    local name; name=$(basename "$(dirname "$f")")
    if ! openssl x509 -checkend 0 -noout -in "$f" >/dev/null 2>&1; then
      problem high "Certificate for $name has EXPIRED" \
        "Visitors get a big scary security warning, and most of them will leave." \
        "sudo certbot renew"
    elif ! openssl x509 -checkend $((14 * 86400)) -noout -in "$f" >/dev/null 2>&1; then
      problem medium "Certificate for $name expires within 14 days" \
        "Auto-renewal should have handled this by now, so it's probably broken." \
        "sudo certbot renew --dry-run   (to test renewal)"
    else
      pass "Certificate for $name is good for 14+ days"
    fi
  done
}

# I can't tell if your backups actually WORK from here. But if there's no
# backup tool on the box at all, that's worth a nudge.
check_backups() {
  section "Backups"
  local t found=""
  for t in restic borg borgmatic rsnapshot timeshift duplicity kopia rclone duplicati; do
    have "$t" && found="$found $t"
  done
  if [ -n "$found" ]; then
    pass "Backup tool(s) found:$found (make sure they actually run, and test a restore!)"
  else
    problem low "No backup tool found" \
      "Security isn't just keeping people out. It's getting back up after a dead disk, a fat-finger or ransomware." \
      "Have a look at restic or borg, and keep a copy OFF this machine."
  fi
}


# ---------------------------------------------------------------------------
# The grade, the monster and the report
# ---------------------------------------------------------------------------

grade_for() {
  local s=$1
  if   [ "$s" -ge 90 ]; then echo A
  elif [ "$s" -ge 75 ]; then echo B
  elif [ "$s" -ge 60 ]; then echo C
  elif [ "$s" -ge 40 ]; then echo D
  else echo F; fi
}

# The best bit. The worse your box, the more bloodshot the eye.
print_monster() {
  local g=$1 eye mood col
  case "$g" in
    A) eye="(  o  )"; mood="It's alive… and SECURE!";                        col="$C_GREEN" ;;
    B) eye="( ~o  )"; mood="Not bad. A few stitches to tighten.";            col="$C_GREEN" ;;
    C) eye="(~~o~ )"; mood="Hmm. This monster needs some work.";             col="$C_YELLOW" ;;
    D) eye="(≈≈O≈≈)"; mood="Yikes. Bloodshot and worried.";                  col="$C_RED" ;;
    *) eye="(#≈@≈#)"; mood="IT'S ALIVE… and wide open. Fix the HIGHs first!"; col="$C_RED" ;;
  esac

  # The art is in a quoted heredoc so bash leaves every backslash alone.
  # EYE is a placeholder that gets swapped for the face above.
  local art
  art=$(cat <<'ART'
    \             /
     \  _______  /
      |/  ___  \|
      | EYE |
    =[|   >_    |]=
      |  ~~~~~  |
      \_|_|_|_|_/
ART
)
  art=${art//EYE/$eye}
  printf '\n%s%s%s\n' "$col" "$art" "$C_RESET"
  printf '  %s%s%s\n' "$C_BOLD" "$mood" "$C_RESET"
}

write_report() {
  [ -n "$REPORT_FILE" ] || return
  {
    echo "# franken-scan report"
    echo
    echo "| | |"
    echo "|---|---|"
    echo "| Host | $(hostname 2>/dev/null) |"
    echo "| System | $DISTRO_NAME ($ARCH, kernel $KERNEL) |"
    echo "| Date | $(date '+%Y-%m-%d %H:%M %Z') |"
    echo "| Ran as | $(is_root && echo 'root (full scan)' || echo 'normal user (some checks skipped)') |"
    echo "| **Grade** | **$GRADE** (score $SCORE/100) |"
    echo "| Problems | $COUNT_HIGH high · $COUNT_MED medium · $COUNT_LOW low |"
    printf '%s\n' "${REPORT_LINES[@]}"
    echo
    echo "---"
    echo "Generated by [franken-scan](https://github.com/MartyMonster/franken-scan) $VERSION. Read-only: nothing on this system was changed."
    echo
    echo "**Want these fixed?** Linux server hardening by MartyMonster: https://martymonster.dev/services#linux"
  } > "$REPORT_FILE" && printf '\n  Report saved to: %s%s%s\n' "$C_BOLD" "$REPORT_FILE" "$C_RESET"
}


# ---------------------------------------------------------------------------
# Off we go
# ---------------------------------------------------------------------------
main() {
  detect_system

  printf '%s\n' "${C_BOLD}franken-scan $VERSION${C_RESET}  ${C_DIM}It's alive!… but is it secure?${C_RESET}"
  printf '%s\n' "${C_DIM}$DISTRO_NAME · $ARCH · kernel $KERNEL · read-only, no network${C_RESET}"
  is_root || printf '%s\n' "${C_YELLOW}Tip: run with sudo for the full scan (a few checks will be skipped).${C_RESET}"

  # Order matters a little: check_ssh works out SSH_PORT, and
  # check_bruteforce uses it later on.
  SSH_PORT=22
  check_ssh
  check_firewall
  check_ports
  check_updates
  check_bruteforce
  check_accounts
  check_docker
  check_files
  check_time
  check_tls
  check_backups

  [ "$SCORE" -lt 0 ] && SCORE=0
  GRADE=$(grade_for "$SCORE")

  print_monster "$GRADE"
  printf '\n  %sGrade: %s%s  (score %d/100)\n' "$C_BOLD" "$GRADE" "$C_RESET" "$SCORE"
  printf '  %d passed · %s%d high%s · %s%d medium%s · %d low · %d skipped\n' \
    "$COUNT_PASS" "$C_RED" "$COUNT_HIGH" "$C_RESET" "$C_YELLOW" "$COUNT_MED" "$C_RESET" "$COUNT_LOW" "$COUNT_SKIP"

  write_report

  printf '\n  %sWant these fixed? → https://martymonster.dev%s\n\n' "$C_DIM" "$C_RESET"

  # Exit code for anyone scripting this: 0 = no HIGH problems, 1 = at least one.
  [ "$COUNT_HIGH" -eq 0 ]
}

main
