#!/usr/bin/env bash
# =============================================================================
# Neo — uninstall / rollback
# Removes files and configs created by Neo. Does NOT uninstall system packages.
#
# Usage:  sudo neo uninstall [--yes] [--dry-run]
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSUME_YES=${ASSUME_YES:-0}
UNINSTALL_DRY=0

for arg in "$@"; do
  case $arg in
    --yes|-y)  ASSUME_YES=1 ;;
    --dry-run) UNINSTALL_DRY=1 ;;
    -h|--help)
      echo "Usage: sudo neo uninstall [--yes] [--dry-run]"
      echo "Rolls back configurations created by Neo while leaving system packages and user data intact."
      exit 0
      ;;
    *) echo "Unknown option: $arg (use --yes, --dry-run or --help)" >&2; exit 2 ;;
  esac
done

# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/messages.sh
source "$ROOT_DIR/lib/messages.sh"
# shellcheck source=lib/os.sh
source "$ROOT_DIR/lib/os.sh"

detect_os 2>/dev/null || true

if (( EUID != 0 )) && (( ! UNINSTALL_DRY )); then
  echo "Run as root: sudo neo uninstall $*" >&2
  exit 1
fi

CONFIRM_MSG="This will remove Neo managed files and restore backup configs.\nPackages installed by Neo are NOT removed.\n\nContinue?"

if (( ! ASSUME_YES )) && (( ! UNINSTALL_DRY )); then
  echo -e "$CONFIRM_MSG"
  read -r -p "Type 'yes' to continue: " reply
  [[ $reply == yes ]] || { echo "Cancelled."; exit 0; }
fi

(( UNINSTALL_DRY )) && echo "==> DRY RUN: nothing is changed, the steps are only shown."
echo "==> Rolling back Neo changes..."

act() {
  if (( UNINSTALL_DRY )); then echo "  [dry-run] $*"; return 0; fi
  "$@"
}

remove_tree() {
  [[ -e $1 ]] || return 0
  if (( UNINSTALL_DRY )); then echo "  [dry-run] would remove: $1"; return 0; fi
  if rm -rf "$1"; then echo "  removed: $1"; else echo "  WARN: could not remove $1"; fi
}

remove() {
  local f
  for f in "$@"; do
    [[ -e $f || -L $f ]] || continue
    if (( UNINSTALL_DRY )); then echo "  [dry-run] would remove: $f"; continue; fi
    if rm -f "$f"; then echo "  removed: $f"; else echo "  WARN: could not remove $f"; fi
  done
}

oldest_backup() {
  local f=$1 b
  while IFS= read -r b; do
    grep -qs 'Managed by neo' "$b" || { printf '%s' "$b"; return 0; }
  done < <(find "$BACKUP_DIR" -maxdepth 1 -name "$(printf '%s' "$f" | tr / _).*" 2>/dev/null | sort)
  return 1
}

restore_or_note() {
  local f=$1 orig
  grep -qs 'Managed by neo' "$f" || return 0
  if orig=$(oldest_backup "$f"); then
    act cp -a "$orig" "$f" && echo "  restored: $f (from backup)"
  else
    echo "  NOTE: $f was written by neo and has no backup; it was left in place."
  fi
}

# ------------------------------------------------------------------ web servers
nginx_users=$(grep -rlsF 'snippets/neo/' /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null \
  | grep -vE '/00-default(-https)?\.conf$' | sort -u || true)

remove /etc/nginx/conf.d/00-neo.conf /etc/nginx/sites-available/00-default.conf \
       /etc/nginx/sites-available/00-default-https.conf /etc/nginx/sites-enabled/00-default.conf \
       /etc/nginx/sites-enabled/00-default-https.conf \
       /etc/nginx/conf.d/00-default.conf /etc/nginx/conf.d/00-default-https.conf

if [[ -n $nginx_users ]]; then
  echo "  KEPT: /etc/nginx/snippets/neo/ (still used by these sites):"
  while IFS= read -r f; do echo "        $f"; done <<<"$nginx_users"
else
  remove /etc/nginx/snippets/neo/security-headers.conf /etc/nginx/snippets/neo/deny-hidden.conf \
         /etc/nginx/snippets/neo/static-cache.conf /etc/nginx/snippets/neo/proxy-params.conf
  [[ -d /etc/nginx/snippets/neo ]] && act rmdir /etc/nginx/snippets/neo 2>/dev/null || true
fi

remove /etc/apache2/conf-available/neo.conf /etc/apache2/conf-enabled/neo.conf \
       /etc/apache2/sites-available/000-neo-default.conf /etc/apache2/sites-enabled/000-neo-default.conf \
       /etc/httpd/conf.d/00-neo.conf /etc/httpd/conf.d/000-neo-default.conf

# ------------------------------------------------------------------ SSH
if [[ -f /etc/ssh/sshd_config.d/00-neo.conf ]]; then
  echo "==> SSH config..."
  remove /etc/ssh/sshd_config.d/00-neo.conf
  if command -v sshd >/dev/null 2>&1; then
    if sshd -t 2>/dev/null; then
      act systemctl reload "$SSH_SERVICE" 2>/dev/null || true
      echo "  reloaded $SSH_SERVICE"
    else
      echo "  WARN: sshd -t failed after removing 00-neo.conf"
    fi
  fi
fi

# ------------------------------------------------------------------ Fail2ban
remove /etc/fail2ban/jail.d/00-neo.conf
restore_or_note /etc/fail2ban/jail.local

# ------------------------------------------------------------------ Ops & Timers
echo "==> Ops, monitoring & timers..."
for unit in neo-backup.timer neo-backup.service neo-health.timer neo-health.service neo-cloudflare-ips.timer neo-cloudflare-ips.service; do
  if [[ -f /etc/systemd/system/$unit ]]; then
    act systemctl disable --now "$unit" 2>/dev/null || true
    remove "/etc/systemd/system/$unit"
  fi
done
act systemctl daemon-reload 2>/dev/null || true

remove /usr/local/bin/neo-backup /usr/local/bin/neo-health /usr/local/sbin/neo-cloudflare-ips

# ------------------------------------------------------------------ Neo State & Symlink
remove /usr/local/bin/neo
remove /run/neo.lock
remove_tree /etc/neo
remove_tree /var/lib/neo

echo "==> Rollback complete."
