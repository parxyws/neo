#!/usr/bin/env bash
# shellcheck shell=bash
# neo doctor: read-only health check. It never changes anything; every finding explains
# what to do next. Exit status: 0 = nothing failed, 1 = at least one check failed.

_DOC_FAIL=0
_doc_ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
_doc_warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
_doc_fail() { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*"; _DOC_FAIL=1; }
_doc_head() { printf '\n%s\n' "$*"; }
_doc_fail_root() { if (( EUID == 0 )); then _doc_fail "$*"; else _doc_warn "$* $(t doctor.need_root)"; fi; }

_doc_system() {
  local rc=0 use avail
  _doc_head "$(t doctor.h.system)"
  if detect_os; then
    os_check || rc=$?
    case $rc in
      0) _doc_ok "$OS_PRETTY" ;;
      3) _doc_fail "$(t doctor.os_eol "$OS_PRETTY")" ;;
      *) _doc_warn "$(t doctor.os_untested "$OS_PRETTY")" ;;
    esac
  else
    _doc_warn "$(t doctor.os_untested "unknown")"
  fi

  use=$(df -P / 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
  if [[ -n $use ]]; then
    if (( use >= 90 )); then _doc_fail "$(t doctor.disk "$use")"
    elif (( use >= 80 )); then _doc_warn "$(t doctor.disk "$use")"
    else _doc_ok "$(t doctor.disk "$use")"; fi
  fi
  avail=$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)
  if [[ -z $avail ]] && command -v sysctl >/dev/null 2>&1; then
    local b; b=$(sysctl -n hw.memsize 2>/dev/null || echo 0); avail=$(( b / 1024 / 1024 ))
  fi
  [[ -n $avail ]] && { if (( avail < 100 )); then _doc_warn "$(t doctor.mem "$avail")"; else _doc_ok "$(t doctor.mem "$avail")"; fi; }

  if [[ -e /var/run/reboot-required ]]; then
    _doc_warn "$(t doctor.reboot)"
  elif command -v needs-restarting >/dev/null 2>&1 && ! needs-restarting -r >/dev/null 2>&1; then
    _doc_warn "$(t doctor.reboot)"
  fi

  local failed
  failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
  if [[ -n ${failed// /} ]]; then _doc_fail "$(t doctor.units_failed "$failed")"
  else _doc_ok "$(t doctor.units_ok)"; fi
}

_doc_access() {
  local port root pass fw=""
  _doc_head "$(t doctor.h.access)"
  if ! command -v sshd >/dev/null 2>&1; then _doc_warn "$(t doctor.no_sshd)"; return 0; fi
  if ! sshd -t >/dev/null 2>&1; then _doc_fail_root "$(t doctor.sshd_invalid)"; return 0; fi
  port=$(sshd -T 2>/dev/null | awk '$1=="port" {print $2; exit}')
  root=$(sshd -T 2>/dev/null | awk '$1=="permitrootlogin" {print $2; exit}')
  pass=$(sshd -T 2>/dev/null | awk '$1=="passwordauthentication" {print $2; exit}')
  _doc_ok "$(t doctor.ssh_port "${port:-22}")"
  if [[ $root == no ]]; then _doc_ok "$(t doctor.root_off)"; else _doc_warn "$(t doctor.root_on)"; fi
  if [[ $pass == no ]]; then _doc_ok "$(t doctor.pass_off)"; else _doc_warn "$(t doctor.pass_on)"; fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    fw=ufw
    if ufw status 2>/dev/null | grep -qE "^(${port:-22}(/tcp)?|OpenSSH|22/tcp \(OpenSSH\))[[:space:]]+ALLOW"; then _doc_ok "$(t doctor.fw_ssh_ok ufw)"
    else _doc_fail "$(t doctor.fw_ssh_missing ufw "${port:-22}")"; fi
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    fw=firewalld
    if firewall-cmd --list-ports 2>/dev/null | grep -qw "${port:-22}/tcp" \
       || { [[ ${port:-22} == 22 ]] && firewall-cmd --list-services 2>/dev/null | grep -qw ssh; }; then
      _doc_ok "$(t doctor.fw_ssh_ok firewalld)"
    else _doc_fail "$(t doctor.fw_ssh_missing firewalld "${port:-22}")"; fi
  fi
  [[ -n $fw ]] || _doc_warn "$(t doctor.fw_off)"

  if command -v fail2ban-client >/dev/null 2>&1; then
    if systemctl is-active --quiet fail2ban 2>/dev/null; then _doc_ok "$(t doctor.f2b_ok)"; else _doc_fail "$(t doctor.f2b_down)"; fi
  fi
}

_doc_web() {
  local any=0 name
  local -a test
  _doc_head "$(t doctor.h.web)"
  for name in nginx apache2 httpd caddy; do
    case $name in
      nginx)   command -v nginx >/dev/null 2>&1 || continue; test=(nginx -t) ;;
      apache2) command -v apache2ctl >/dev/null 2>&1 || continue; test=(apache2ctl configtest) ;;
      httpd)   if ! command -v httpd >/dev/null 2>&1 || command -v apache2ctl >/dev/null 2>&1; then continue; fi
               test=(httpd -t) ;;
      caddy)   command -v caddy >/dev/null 2>&1 || continue; test=(caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile) ;;
    esac
    any=1
    if "${test[@]}" >/dev/null 2>&1; then
      if systemctl is-active --quiet "$name" 2>/dev/null; then _doc_ok "$(t doctor.web_ok "$name")"
      else _doc_fail "$(t doctor.web_down "$name")"; fi
    else
      _doc_fail_root "$(t doctor.web_invalid "$name" "${test[*]}")"
    fi
  done
  (( any )) || _doc_ok "$(t doctor.web_none)"

  local cert dom
  for cert in /etc/letsencrypt/live/*/cert.pem; do
    [[ -e $cert ]] || continue
    dom=$(basename "$(dirname "$cert")")
    if openssl x509 -checkend $((21 * 86400)) -noout -in "$cert" >/dev/null 2>&1; then
      _doc_ok "$(t doctor.cert_ok "$dom")"
    else
      _doc_fail "$(t doctor.cert_expiring "$dom")"
    fi
  done
}

_doc_backups() {
  local newest age
  [[ -e /usr/local/bin/neo-backup ]] || return 0
  _doc_head "$(t doctor.h.backups)"
  if tail -n 30 /var/log/neo-backup.log 2>/dev/null | grep -q 'RESULT: at least one backup FAILED'; then
    _doc_fail "$(t doctor.backup_failed)"
  fi
  newest=$(find /var/backups/neo/db -name '*.sql.gz' -exec stat -f '%m' {} + 2>/dev/null | sort -n | tail -n 1 || true)
  if [[ -z $newest ]]; then
    newest=$(find /var/backups/neo/db -name '*.sql.gz' -printf '%T@\n' 2>/dev/null | sort -n | tail -n 1 || true)
  fi
  if [[ -z $newest ]]; then
    _doc_warn "$(t doctor.backup_none)"
  else
    newest=${newest%%.*}
    age=$(( ($(date +%s) - newest) / 3600 ))
    if (( age > 30 )); then _doc_fail "$(t doctor.backup_old "$age")"
    else _doc_ok "$(t doctor.backup_ok "$age")"; fi
  fi
}

neo_doctor() {
  _DOC_FAIL=0
  printf '%s\n' "$(t doctor.title)"
  if (( EUID != 0 )); then log_warn "$(t doctor.not_root)"; fi

  _doc_system
  _doc_access
  _doc_web
  _doc_backups

  printf '\n'
  if (( _DOC_FAIL == 0 )); then
    log_ok "$(t doctor.result_ok)"
    return 0
  else
    log_err "$(t doctor.result_fail)"
    return 1
  fi
}

neo_status() {
  printf '\033[1;36m=== 🐱 Neo Server Status ===\033[0m\n'

  local up
  up=$(uptime -p 2>/dev/null | sed 's/up //' || uptime 2>/dev/null | awk -F',  ' '{print $1}')
  printf '  \033[1mUptime:\033[0m   %s\n' "${up:-unknown}"

  if [[ -r /proc/loadavg ]]; then
    printf '  \033[1mLoad:\033[0m     %s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"
  elif command -v sysctl >/dev/null 2>&1; then
    printf '  \033[1mLoad:\033[0m     %s\n' "$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2,$3,$4}' || echo "N/A")"
  fi

  if command -v free >/dev/null 2>&1; then
    local mem swap
    mem=$(free -h 2>/dev/null | awk '/^Mem:/{print $3 " / " $2}')
    swap=$(free -h 2>/dev/null | awk '/^Swap:/{print $3 " / " $2}')
    [[ -n $mem ]] && printf '  \033[1mMemory:\033[0m   %s\n' "$mem"
    [[ -n $swap ]] && printf '  \033[1mSwap:\033[0m     %s\n' "$swap"
  fi

  local disk
  disk=$(df -h / 2>/dev/null | awk 'NR==2{print $3 " / " $2 " (" $5 ")"}')
  [[ -n $disk ]] && printf '  \033[1mDisk /:\033[0m   %s\n' "$disk"

  printf '\n\033[1;36m=== Services ===\033[0m\n'
  local any_svc=0
  for svc in ssh sshd fail2ban ufw firewalld nginx apache2 httpd caddy php-fpm postgresql mysql mariadb \
             redis-server redis docker podman.socket unattended-upgrades dnf-automatic.timer neo-backup.timer; do
    systemctl cat "$svc" >/dev/null 2>&1 || continue
    any_svc=1
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      printf '  \033[1;32m✓\033[0m %s\n' "$svc"
    elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
      printf '  \033[1;31m✗\033[0m %s (\033[33m%s\033[0m)\n' "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo inactive)"
    fi
  done
  for unit in $(systemctl list-units --type=service --all --no-legend 'php*-fpm.service' 2>/dev/null | awk '{print $1}' | grep -E '^php[0-9.]+-fpm' || true); do
    any_svc=1
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      printf '  \033[1;32m✓\033[0m %s\n' "$unit"
    else
      printf '  \033[1;31m✗\033[0m %s\n' "$unit"
    fi
  done
  (( any_svc == 0 )) && printf '  \033[2mNo managed services installed yet\033[0m\n'

  printf '\n\033[1;36m=== Backups ===\033[0m\n'
  local bdir=${BACKUP_DIR:-/var/backups/neo}/db
  if [[ -d $bdir ]]; then
    local count
    count=$(find "$bdir" -name '*.sql.gz' 2>/dev/null | wc -l)
    printf '  Database backups: %d files\n' "$count"
    find "$bdir" -name '*.sql.gz' -exec stat -c '%y %s %n' {} + 2>/dev/null | sort -r | head -n 3 | awk '{print "    " $1, $2, "(" $4 " bytes)"}' || true
  else
    printf '  \033[2mNo backup directory yet\033[0m\n'
  fi

  printf '\n\033[1;36m=== Security Events (24h) ===\033[0m\n'
  if command -v journalctl >/dev/null 2>&1; then
    local fails
    fails=$(journalctl -u ssh -u sshd --since "1 day ago" -o cat 2>/dev/null | grep -E "Failed password|Invalid user" 2>/dev/null | wc -l)
    fails=${fails//[[:space:]]/}
    printf '  Failed SSH attempts: %s\n' "${fails:-0}"
  else
    printf '  \033[2mjournalctl not available\033[0m\n'
  fi
  return 0
}
