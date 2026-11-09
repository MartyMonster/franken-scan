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
#    - it only LOOKS. It never changes your configuration: no installs,
#      no edits, no service restarts. (Honest small print: tools it asks,
#      like dnf or zypper, may write to their own log files, and reading
#      files can bump their "last accessed" time. That's the OS, not us.)
#    - it never contacts the internet or phones home. No telemetry, nothing.
#    - it's one bash file with nothing to install.
#
#  The only file it ever creates is the report, and only if you ask for one
#  with --report. Even then it refuses to overwrite anything that's already there.
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

VERSION="1.0.1"


# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

USE_COLOR=1
QUIET=0
SHOW_MONSTER=0
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
  --monster         say hello to the monster (that's all it does)
  -h, --help        this help

Tip: run with sudo for the full scan. Without it, a few checks get skipped
(you'll see which ones). franken-scan never changes your configuration and
never contacts the internet. With --report it creates one new file, and it
won't overwrite an existing one.
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
    --monster)  SHOW_MONSTER=1 ;;
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

# How wide to wrap text. Use the terminal's width, but cap it at 100 because
# really long lines are hard to read, and fall back to 80 if we can't tell.
TERM_WIDTH=$( { [ -t 1 ] && tput cols 2>/dev/null; } || echo 80)
[ "$TERM_WIDTH" -gt 100 ] 2>/dev/null && TERM_WIDTH=100
[ "$TERM_WIDTH" -lt 40 ] 2>/dev/null && TERM_WIDTH=40

# wrap INDENT "first-line prefix" "text"
# Word-wraps text to the terminal width. The first line starts with the
# prefix (e.g. "      Why: "); every line after that is indented by INDENT
# spaces so it sits neatly under the first. The prefix's VISIBLE width should
# equal INDENT (colour codes don't count).
wrap() {
  local indent="$1" prefix="$2" text="$3" pad
  pad=$(printf '%*s' "$indent" '')
  printf '%s\n' "$text" | fold -s -w $((TERM_WIDTH - indent)) | {
    IFS= read -r first && printf '%s%s\n' "$prefix" "$first"
    while IFS= read -r line; do printf '%s%s\n' "$pad" "$line"; done
  }
}

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
  [ "$QUIET" -eq 1 ] || wrap 4 "  ${C_GREEN}✓${C_RESET} " "$1"
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
  # Title, then "Why" and "Fix" lined up underneath, each wrapped to fit.
  wrap 4 "  ${colour}✗${C_RESET} " "${colour}[${label}]${C_RESET} $title"
  wrap 9 "    ${C_DIM}Why:${C_RESET} " "$why"
  [ -n "$fix" ] && wrap 9 "    ${C_DIM}Fix:${C_RESET} " "$C_BOLD$fix$C_RESET"
  REPORT_LINES+=("- ❌ **[$label] $title**" "  - Why: $why")
  [ -n "$fix" ] && REPORT_LINES+=("  - Fix: \`$fix\`")
}

# Worth knowing, but not something you get marked down for.
info() {
  [ "$QUIET" -eq 1 ] || wrap 4 "  ${C_BLUE}i${C_RESET} " "$1"
  REPORT_LINES+=("- ℹ️ $1")
}

# Couldn't check it. I'd rather say so honestly than quietly pretend it passed.
skip() {
  COUNT_SKIP=$((COUNT_SKIP + 1))
  [ "$QUIET" -eq 1 ] || wrap 4 "  ${C_GREY}-${C_RESET} " "${C_GREY}skipped: $1${C_RESET}"
  REPORT_LINES+=("- ⏭️ Skipped: $1")
}

have()       { command -v "$1" >/dev/null 2>&1; }
is_root()    { [ "$(id -u)" -eq 0 ]; }
svc_active() { have systemctl && systemctl is-active --quiet "$1" 2>/dev/null; }

# Members of a group, read straight from /etc/group. (Deliberately NOT
# "getent": on machines joined to LDAP/AD that would ask a server over the
# network, and we promised not to do that.)
group_members() { awk -F: -v g="$1" '$1 == g {print $4}' /etc/group 2>/dev/null; }

# The SSH service is called "ssh" on Debian/Ubuntu and "sshd" everywhere else.
ssh_service() { [ "$FAMILY" = "debian" ] && echo ssh || echo sshd; }

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
    # Read os-release as plain text rather than "source"-ing it. Sourcing would
    # RUN it as shell code, as root, which is a bad idea for a security tool.
    osr() { sed -n "s/^$1=//p" /etc/os-release | head -n1 | tr -d '"'"'"; }
    DISTRO_NAME=$(osr PRETTY_NAME); [ -n "$DISTRO_NAME" ] || DISTRO_NAME=$(osr NAME)
    local ids; ids="$(osr ID) $(osr ID_LIKE)"
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

  # "sshd -T" prints the REAL settings after every Include, Match default and
  # built-in default has been applied. It needs root, and that's the only
  # source I trust. I used to guess from the config files without root, but
  # Include ordering made the guess wrong in both directions, so now it's
  # simply "run with sudo" rather than a confident wrong answer.
  #
  # Lower-cased because older OpenSSH prints "passwordauthentication" and
  # newer ones print "PasswordAuthentication". (That one caught me out: the
  # script happily told me my keys-only box accepted passwords.)
  if ! is_root; then
    skip "SSH settings (need sudo to read the real, effective SSH settings)"
    return
  fi
  local cfg
  if ! cfg=$("$sshd_bin" -T 2>/dev/null) || [ -z "$cfg" ]; then
    skip "SSH settings ('sshd -T' failed. Is the SSH config valid? Try: sudo sshd -t)"
    return
  fi
  cfg=$(printf '%s\n' "$cfg" | tr '[:upper:]' '[:lower:]')
  ssh_opt() { printf '%s\n' "$cfg" | awk -v k="$1" '$1==k {print $2; exit}'; }

  # Where to put a fix. Most distros read /etc/ssh/sshd_config.d/ FIRST, and
  # sshd keeps the first value it sees, so a drop-in file wins over the main
  # file. "sshd -t" checks the config before reloading, so a typo can't
  # take SSH down.
  local where="add it to a new file /etc/ssh/sshd_config.d/00-hardening.conf"
  local apply; apply="sudo sshd -t && sudo systemctl reload $(ssh_service)"

  # Can a PASSWORD get someone in? Two routes: PasswordAuthentication, and
  # keyboard-interactive via PAM (which usually asks for... a password).
  # Turning off only the first leaves the second wide open.
  local pw kbd pam pw_possible=no
  pw=$(ssh_opt passwordauthentication)
  kbd=$(ssh_opt kbdinteractiveauthentication); [ -n "$kbd" ] || kbd=$(ssh_opt challengeresponseauthentication)
  pam=$(ssh_opt usepam)
  if [ "${pw:-yes}" = "yes" ]; then
    pw_possible=yes
    problem high "SSH accepts passwords" \
      "Passwords can be guessed by bots. SSH keys can't. (Make sure your key login works BEFORE turning passwords off, and keep your current session open while you test!)" \
      "Set 'PasswordAuthentication no': $where, then: $apply"
  elif [ "${kbd:-yes}" = "yes" ] && [ "${pam:-no}" = "yes" ]; then
    pw_possible=yes
    problem high "SSH can still ask for a password (keyboard-interactive via PAM)" \
      "PasswordAuthentication is off, but this second login route usually asks for a password anyway, so bots can still guess." \
      "Set 'KbdInteractiveAuthentication no': $where, then: $apply"
  else
    pass "SSH doesn't accept passwords (keys only, unless AuthenticationMethods says otherwise)"
  fi

  # Root login. How bad it is depends on whether passwords work at all.
  local root_login; root_login=$(ssh_opt permitrootlogin)
  case "${root_login:-prohibit-password}" in
    no)
      pass "Root can't log in over SSH" ;;
    forced-commands-only)
      pass "Root can only run pre-set commands over SSH (forced-commands-only)" ;;
    prohibit-password|without-password)
      problem low "Root can log in over SSH with a key" \
        "Logging in as a normal user and using sudo leaves a clearer trail and limits the damage if a key leaks." \
        "Set 'PermitRootLogin no': $where, then: $apply" ;;
    *)
      if [ "$pw_possible" = "yes" ]; then
        problem high "Root can log in over SSH with a password" \
          "Bots try root passwords against every server on the internet, all day, every day." \
          "Set 'PermitRootLogin no': $where, then: $apply"
      else
        problem low "Root can log in over SSH (keys only, as passwords are off)" \
          "Logging in as a normal user and using sudo leaves a clearer trail and limits the damage if a key leaks." \
          "Set 'PermitRootLogin no': $where, then: $apply"
      fi ;;
  esac

  # Every port sshd is set to use. Moving off 22 cuts log spam but isn't real
  # security, so it's only mentioned. The ports are reused by the firewall
  # advice and the brute-force check.
  SSH_PORTS=$(printf '%s\n' "$cfg" | awk '$1=="port" {print $2}' | sort -un | paste -sd ' ' -)
  SSH_PORTS=${SSH_PORTS:-22}
  info "SSH is set to use port(s): $SSH_PORTS."
}

check_firewall() {
  section "Firewall"

  # A firewall SERVICE running isn't the same as a firewall actually
  # blocking anything. (A ufw with "allow incoming", or an nftables
  # "accept everything", looks active but protects nothing.) So I only give
  # a pass when the rules show incoming traffic is actually dropped by
  # default, and that needs root to see.
  if ! is_root; then
    local svc
    for svc in ufw firewalld nftables; do
      if svc_active "$svc"; then
        skip "Firewall rules ($svc is running, but sudo is needed to check it actually blocks anything)"
        return
      fi
    done
    skip "Firewall (need sudo to read the rules; no firewall service seen running)"
    return
  fi

  local verdict="" detail=""

  if have ufw && ufw status 2>/dev/null | grep -q "Status: active"; then
    if ufw status verbose 2>/dev/null | grep -qE "Default: (deny|reject) \(incoming\)"; then
      verdict=pass; detail="ufw is on and blocks incoming connections by default"
    else
      verdict=weak; detail="ufw is on, but it ALLOWS incoming connections by default"
    fi
  elif svc_active firewalld && have firewall-cmd; then
    local zone; zone=$(firewall-cmd --get-default-zone 2>/dev/null)
    if [ "$zone" = "trusted" ]; then
      verdict=weak; detail="firewalld is on, but the default zone is 'trusted' (lets everything in)"
    elif [ -n "$zone" ]; then
      verdict=pass; detail="firewalld is on (default zone: $zone)"
    fi
  elif have nft && nft list ruleset 2>/dev/null | grep -qE "hook input .*policy (drop|reject)"; then
    verdict=pass; detail="nftables drops incoming traffic by default"
  elif have iptables && iptables -S INPUT 2>/dev/null | grep -qE "^-P INPUT (DROP|REJECT)|^-A INPUT -j (DROP|REJECT)$"; then
    verdict=pass; detail="iptables drops incoming traffic by default (IPv4)"
  elif have nft && nft list ruleset 2>/dev/null | grep -q "hook input"; then
    verdict=unknown; detail="nftables has input rules, but the default is 'accept', so I can't tell what's actually blocked"
  fi

  # The fix: Fedora/RHEL get firewalld, everyone else gets ufw (the easiest
  # to learn). The SSH port(s) are allowed FIRST, which is the bit that
  # stops people locking themselves out of a remote server.
  local fw_fix allow="" port
  for port in ${SSH_PORTS:-22}; do allow="$allow sudo ufw allow $port/tcp &&"; done
  case "$FAMILY" in
    fedora) fw_fix="sudo dnf install firewalld && sudo systemctl enable --now firewalld   (SSH on port 22 is allowed by default; for another port first run: sudo firewall-cmd --permanent --add-port=PORT/tcp)" ;;
    *)      fw_fix="$(install_cmd ufw) &&$allow sudo ufw default deny incoming && sudo ufw enable" ;;
  esac

  case "$verdict" in
    pass)    pass "$detail" ;;
    weak)    problem high "$detail" \
               "A firewall that lets everything in is the same as no firewall at all." \
               "$fw_fix" ;;
    unknown) skip "Firewall: $detail" ;;
    *)       problem high "No active firewall found" \
               "Without a firewall, every service you run is reachable from the internet, including the ones you forgot about." \
               "$fw_fix" ;;
  esac
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
  # pending stays EMPTY if we couldn't find out, which is reported as
  # skipped, never as "no updates". (An empty answer from a failed command
  # looks exactly like "all good", and that's how scanners lie to you.)
  local pending="" out rc

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
      # dnf's exit code: 0 = nothing to update, 100 = updates available,
      # anything else = it couldn't tell (e.g. no cache yet).
      if have dnf; then
        out=$(dnf -C -q check-update 2>/dev/null); rc=$?
        case "$rc" in
          0)   pending=0 ;;
          100) pending=$(printf '%s\n' "$out" | awk 'NF==3 && $1 ~ /\./ {n++} END {print n+0}') ;;
        esac
      fi ;;
    suse)
      # --no-refresh = use what's already downloaded. Rows that are updates start with "v |".
      if have zypper; then
        out=$(zypper --no-refresh -q list-updates 2>/dev/null) && pending=$(printf '%s\n' "$out" | grep -c '^v ')
      fi ;;
  esac

  if [ -z "$pending" ]; then
    skip "Pending updates (couldn't read the package cache. Run your package manager's refresh first, e.g. $(update_cmd))"
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
      # Only count a real setting, not one that's commented out.
      if grep -qsE '^[[:space:]]*APT::Periodic::Unattended-Upgrade[[:space:]]+"1"' /etc/apt/apt.conf.d/*; then
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

# The right way to install a package on THIS system, so we only ever show
# one fix command instead of a "Debian: … · Fedora: … · Arch: …" wall.
install_cmd() {
  case "$FAMILY" in
    debian) echo "sudo apt install $1" ;;
    arch)   echo "sudo pacman -S $1" ;;
    fedora) echo "sudo dnf install $1" ;;
    suse)   echo "sudo zypper install $1" ;;
    *)      echo "install '$1' with your package manager" ;;
  esac
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

  # Only really matters if SSH is reachable from outside. If not, no nagging.
  local public=no port
  for port in ${SSH_PORTS:-22}; do listening_publicly "$port" && public=yes; done

  # fail2ban running doesn't mean it's watching SSH. That needs an "sshd" jail.
  if svc_active fail2ban; then
    if ! is_root; then
      skip "fail2ban is running (need sudo to check it's actually watching SSH)"
    elif fail2ban-client status 2>/dev/null | grep -qi "ssh"; then
      pass "fail2ban is watching SSH (it bans IPs after repeated failed logins)"
    else
      problem low "fail2ban is running but has no SSH jail" \
        "It's installed and running, but it isn't watching SSH logins, so it isn't blocking anyone." \
        "Create /etc/fail2ban/jail.local containing: [sshd] enabled = true   then: sudo systemctl restart fail2ban"
    fi
  elif svc_active crowdsec || svc_active sshguard; then
    pass "Brute-force protection is running ($(svc_active crowdsec && echo crowdsec || echo sshguard))"
  elif [ "$public" = "yes" ]; then
    problem medium "No brute-force blocker running" \
      "Bots hammer SSH with guesses around the clock. fail2ban or CrowdSec bans them after a few failures." \
      "$(install_cmd fail2ban) && sudo systemctl enable --now fail2ban"
  else
    info "No brute-force blocker running, but SSH isn't open publicly, so that's fine."
  fi
}

check_accounts() {
  section "User accounts"

  # Not a problem by itself. It's just a good moment to ask "should all of
  # these people still have the keys to the kingdom?"
  local admins
  admins=$(for g in sudo wheel admin; do group_members "$g"; done \
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
  local members; members=$(group_members docker)
  [ -n "$members" ] && info "Users in the 'docker' group (effectively root access): $members"

  # What matters is whether "others" (everyone) can WRITE to it: the 2-bit
  # of the last permission digit. 666, 667, 777… all count.
  local mode; mode=$(stat -c '%a' /var/run/docker.sock 2>/dev/null)
  if [ -z "$mode" ]; then
    skip "Docker socket permissions (couldn't read them)"
  elif (( 8#$mode & 2 )); then
    problem high "Docker socket is writable by every user (mode $mode)" \
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
  # -H follows the starting folders if they're symlinks (on Arch /usr/sbin
  # is just a link to /usr/bin, and plain find would skip it).
  local ww dirs=() d
  for d in /etc /usr/bin /usr/sbin /usr/lib/systemd; do [ -e "$d" ] && dirs+=("$d"); done
  ww=$(find -H "${dirs[@]}" -xdev -type f -perm -0002 2>/dev/null | head -n 10 | paste -sd ' ' -)
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

# The easter egg (--monster). Just the head. He's had enough of his body.
print_monster() {
  printf '%s' "$C_GREEN"
  cat <<'MONSTER'
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
MONSTER
  printf '%s\n  %sIt'\''s alive!%s\n\n' "$C_RESET" "$C_BOLD" "$C_RESET"
}

# The big "franken-scan" lettering at the top (figlet's "Slant" font).
# It's in a quoted heredoc so bash leaves every backslash and backtick
# alone. 67 columns wide, so it still fits an 80-column SSH session.
print_banner() {
  printf '%s' "$C_GREEN"
  cat <<'BANNER'
    ____                 __
   / __/________ _____  / /_____  ____        ______________ _____
  / /_/ ___/ __ `/ __ \/ //_/ _ \/ __ \______/ ___/ ___/ __ `/ __ \
 / __/ /  / /_/ / / / / ,< /  __/ / / /_____(__  ) /__/ /_/ / / / /
/_/ /_/   \__,_/_/ /_/_/|_|\___/_/ /_/     /____/\___/\__,_/_/ /_/
BANNER
  printf '%s' "$C_RESET"
  printf '  %sv%s · It'\''s alive!… but is it secure?%s\n' "$C_DIM" "$VERSION" "$C_RESET"
  printf '  %s%s · %s · kernel %s · read-only, never contacts the internet%s\n' "$C_DIM" "$DISTRO_NAME" "$ARCH" "$KERNEL" "$C_RESET"
  is_root || printf '  %sTip: run with sudo for the full scan (a few checks will be skipped).%s\n' "$C_YELLOW" "$C_RESET"
}

# The result at the end: grade, counts and a one-line verdict. Kept plain on
# purpose: the banner up top is the only artwork.
print_summary() {
  local g=$1 mood col
  case "$g" in
    A) mood="It's alive… and SECURE!";                         col="$C_GREEN" ;;
    B) mood="Not bad. A few stitches to tighten.";             col="$C_GREEN" ;;
    C) mood="Hmm. This monster needs some work.";              col="$C_YELLOW" ;;
    D) mood="Yikes. Plenty to fix.";                           col="$C_RED" ;;
    *) mood="IT'S ALIVE… and wide open. Fix the HIGHs first!"; col="$C_RED" ;;
  esac

  # Skipped checks mean we didn't see everything, so don't hand out a
  # confident "SECURE!" on a half-finished scan.
  if [ "$COUNT_SKIP" -gt 0 ]; then
    mood="Incomplete: $COUNT_SKIP check(s) skipped$(is_root || echo ', run with sudo for the full picture')."
  fi

  printf '\n%s── Result ──%s\n' "$C_BOLD$C_BLUE" "$C_RESET"
  printf '  %sGrade %s%s · %d/100 · %s\n' "$C_BOLD$col" "$g" "$C_RESET" "$SCORE" "$mood"
  printf '  %d passed · %s%d high%s · %s%d medium%s · %d low · %d skipped\n' \
    "$COUNT_PASS" "$C_RED" "$COUNT_HIGH" "$C_RESET" "$C_YELLOW" "$COUNT_MED" "$C_RESET" "$COUNT_LOW" "$COUNT_SKIP"
}

write_report() {
  [ -n "$REPORT_FILE" ] || return

  # Never overwrite anything, and never follow a symlink. If you're running
  # as root and someone has planted a link called "franken-scan-report-…"
  # pointing at /etc/shadow, a plain ">" would happily trash it. So: refuse
  # if the name already exists in ANY form, and create the file with
  # noclobber (bash then opens it with O_EXCL, which won't follow links).
  if [ -e "$REPORT_FILE" ] || [ -L "$REPORT_FILE" ]; then
    printf '\n  %sNot saving the report: "%s" already exists. Pick another name with --report FILE.%s\n' "$C_YELLOW" "$REPORT_FILE" "$C_RESET"
    return
  fi
  ( set -o noclobber; {
    echo "# franken-scan report"
    echo
    echo "| | |"
    echo "|---|---|"
    echo "| Host | $(hostname 2>/dev/null) |"
    echo "| System | $DISTRO_NAME ($ARCH, kernel $KERNEL) |"
    echo "| Date | $(date '+%Y-%m-%d %H:%M %Z') |"
    echo "| Ran as | $(is_root && echo 'root (full scan)' || echo 'normal user (some checks skipped)') |"
    echo "| **Grade** | **$GRADE** (score $SCORE/100) |"
    echo "| Problems | $COUNT_HIGH high · $COUNT_MED medium · $COUNT_LOW low · $COUNT_SKIP skipped |"
    printf '%s\n' "${REPORT_LINES[@]}"
    echo
    echo "---"
    echo "Generated by [franken-scan](https://github.com/MartyMonster/franken-scan) $VERSION. It only reads: no configuration was changed and nothing was sent anywhere."
    echo
    echo "**Want these fixed?** Linux server hardening by MartyMonster: https://martymonster.dev/services#linux"
  } > "$REPORT_FILE" ) 2>/dev/null \
    && printf '\n  Report saved to: %s%s%s\n' "$C_BOLD" "$REPORT_FILE" "$C_RESET" \
    || printf '\n  %sCould not save the report to "%s".%s\n' "$C_YELLOW" "$REPORT_FILE" "$C_RESET"
}


# ---------------------------------------------------------------------------
# Off we go
# ---------------------------------------------------------------------------
main() {
  if [ "$SHOW_MONSTER" -eq 1 ]; then print_monster; exit 0; fi
  detect_system

  print_banner

  # Order matters a little: check_ssh works out SSH_PORTS, and the
  # firewall and brute-force checks use it later on.
  SSH_PORTS=22
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

  print_summary "$GRADE"

  write_report

  printf '\n  %sWant these fixed? → https://martymonster.dev%s\n\n' "$C_DIM" "$C_RESET"

  # Exit code for anyone scripting this: 0 = no HIGH problems, 1 = at least one.
  [ "$COUNT_HIGH" -eq 0 ]
}

main
