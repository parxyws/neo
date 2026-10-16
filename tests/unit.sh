#!/usr/bin/env bash
# Unit tests for validators, helpers, and OS checks (no root, no changes to the system).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
DRY_RUN=1; ASSUME_YES=1; LOG_FILE=/tmp/neo-unit.log
# shellcheck source=lib/common.sh
source lib/common.sh
# shellcheck source=lib/os.sh
source lib/os.sh

fail=0
ok()  { "$@" || { echo "FAIL (expected ok): $*"; fail=1; }; }
bad() { if "$@"; then echo "FAIL (expected reject): $*"; fail=1; fi; }

_stat_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
_stat_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# Username validators
ok  valid_username deploy
ok  valid_username web_01
bad valid_username Root
bad valid_username "1abc"
bad valid_username "a b"

# SSH port validators
ok  valid_ssh_port 22
ok  valid_ssh_port 2222
bad valid_ssh_port 80
bad valid_ssh_port 70000
bad valid_ssh_port abc

# Hostname validators
ok  valid_hostname web-01
bad valid_hostname -bad
bad valid_hostname "a_b"

# Port list validators
ok  valid_port_list "3000, 8080/tcp 51820/udp"
bad valid_port_list "3000/icmp"
bad valid_port_list "99999"
bad valid_port_list ""

# SSH pubkey validators
ok  valid_ssh_pubkey "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl me@x"
bad valid_ssh_pubkey "ssh-ed25519 notbase64!!"
bad valid_ssh_pubkey 'command="x" ssh-ed25519 AAAA'

# Domain and email validators
ok  valid_domain example.com
ok  valid_domain app.sub.example.com
bad valid_domain -example.com
bad valid_domain "example..com"
ok  valid_email user@example.com
bad valid_email "user@bad"

# normalize_domain
[[ $(normalize_domain "HTTPS://Example.COM/test?q=1") == "example.com" ]] || { echo "FAIL: normalize_domain"; fail=1; }

# Distro matrix checks
test_distro() {
  OS_ID=$1
  OS_VERSION=$2
  os_check
}
ok test_distro ubuntu 20.04
ok test_distro ubuntu 22.04
ok test_distro ubuntu 24.04
ok test_distro debian 11
ok test_distro debian 12
ok test_distro debian 13
ok test_distro almalinux 8
ok test_distro almalinux 9
ok test_distro rocky 8
ok test_distro rocky 9
ok test_distro amzn 2023
ok test_distro fedora 40
bad test_distro archlinux rolling

# write_file must be idempotent and never touch disk in dry-run
tmp=$(mktemp -d)
DRY_RUN=0
printf 'a\n' | write_file "$tmp/f" 600
before=$(_stat_mtime "$tmp/f")
sleep 1
printf 'a\n' | write_file "$tmp/f" 600
[[ $(_stat_mtime "$tmp/f") == "$before" ]] || { echo "FAIL: write_file rewrote identical content"; fail=1; }
[[ $(_stat_mode "$tmp/f") == 600 ]] || { echo "FAIL: mode not applied"; fail=1; }
DRY_RUN=1
printf 'b\n' | write_file "$tmp/g" 600 >/dev/null
[[ -e $tmp/g ]] && { echo "FAIL: dry-run wrote a file"; fail=1; }
rm -rf "$tmp"

# _same_file must work without cmp
tmp=$(mktemp -d); mkdir "$tmp/bin"; ln -s "$(command -v cat)" "$tmp/bin/cat"
same_nocmp() { env PATH="$tmp/bin" "$BASH" -c "source lib/common.sh; _same_file \"\$1\" \"\$2\"" _ "$@"; }
printf 'a\n' >"$tmp/1"; printf 'a\n' >"$tmp/2"; printf 'a' >"$tmp/3"; printf 'b\n' >"$tmp/4"
ok  same_nocmp "$tmp/1" "$tmp/2"
bad same_nocmp "$tmp/1" "$tmp/3"
bad same_nocmp "$tmp/1" "$tmp/4"
rm -rf "$tmp"

(( fail )) && echo "UNIT TESTS FAILED" || echo "unit tests passed"
exit $fail
