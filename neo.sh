#!/usr/bin/env bash
# =============================================================================
# Neo — production-grade Linux server setup and management CLI tool
# Usage:  sudo neo [command] [options]      (see --help)
# =============================================================================
set -uo pipefail
: "${LC_ALL:=C.UTF-8}"
: "${LANG:=C.UTF-8}"
export LC_ALL LANG

VERSION="1.0.0"

_resolve_root() {
  local target="${BASH_SOURCE[0]}"
  while [[ -L "$target" ]]; do
    local dir; dir="$(cd -P "$(dirname "$target")" && pwd)"
    target="$(readlink "$target")"
    [[ $target != /* ]] && target="$dir/$target"
  done
  cd -P "$(dirname "$target")" && pwd
}
ROOT_DIR="$(_resolve_root)"
export PATH="$PATH:/usr/sbin:/sbin:/usr/local/sbin"

DRY_RUN=0
ASSUME_YES=0
PRESET=""
CMD=""
SUBCMD=""
declare -a SELECTED=()
declare -A PRESET_SET=()

# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/messages.sh
source "$ROOT_DIR/lib/messages.sh"
# shellcheck source=lib/os.sh
source "$ROOT_DIR/lib/os.sh"
# shellcheck source=lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=lib/manage.sh
source "$ROOT_DIR/lib/manage.sh"
# shellcheck source=lib/doctor.sh
source "$ROOT_DIR/lib/doctor.sh"

usage() {
  cat <<EOF
Neo $VERSION — production-grade Linux server setup and management.

Usage:
  sudo neo [command] [options]

Commands:
  setup [options]       Configure server step-by-step or with presets
  doctor                Run read-only health checks on system, security, web, and backups
  status | health       Display real-time server health dashboard (neo-health)
  site list             List all websites configured by Neo
  site add [options]    Add a new website with Let's Encrypt HTTPS
  site remove <domain>  Safely remove a website (configs backed up, files preserved)
  db list               List active PostgreSQL and MySQL databases
  db create [options]   Create a new database and dedicated user
  db drop <name>        Safely drop a database (dump is saved first)
  cloudflare            Configure Cloudflare real visitor IP restoration
  dokploy [cmd]         Install or manage Dokploy PaaS (setup, status, update)
  update                Update Neo to the latest version
  uninstall             Roll back Neo configuration (preserves packages and site files)

Setup Options:
  --preset NAME         recommended | minimal | custom | domain | database | cloudflare
  --dry-run             Preview changes without modifying the server
  -y, --yes             Non-interactive mode (requires --preset)
  --ssh-key "KEY"       Public SSH key for admin user
  --webserver NAME      nginx | caddy | apache (default: nginx)

Site Add Options:
  --domain DOMAIN       Domain name to configure
  --site-type TYPE      static | spa | proxy | laravel | php | wordpress | redirect
  --port PORT           Backend port for proxy apps (default: 3000)
  --redirect-to URL     Destination for redirect sites
  --app-cmd "CMD"       Service startup command for proxy apps
  --hsts                Enable HTTP Strict Transport Security
  --no-workers          Skip Laravel queue worker and scheduler

Site Remove Options:
  --purge-files         Move /var/www/<domain> to /var/backups/neo/removed-sites/
  --keep-cert           Keep the Let's Encrypt certificate

Database Options:
  --engine ENGINE       postgresql | mysql (default: postgresql)
  --db NAME             Database name
  --db-user USER        Database user (defaults to database name)

General Options:
  -v, --version         Print version
  -h, --help            Show this help reference

Examples:
  sudo neo                                # interactive setup wizard
  sudo neo doctor                         # read-only server health audit
  sudo neo setup --preset recommended     # recommended server stack
  sudo neo site add                       # guided website wizard
  sudo neo site list                      # list configured websites
  sudo neo site remove example.com        # remove website safely
  sudo neo db list                        # show active databases
  sudo neo db drop myapp                  # safe database removal with dump
EOF
}

# ------------------------------------------------------------------ command routing
parse_args() {
  # Consume leading global options
  while (( $# )); do
    case "$1" in
      -h|--help|help) usage; exit 0 ;;
      -v|--version|version) echo "neo $VERSION"; exit 0 ;;
      --dry-run) DRY_RUN=1; shift ;;
      -y|--yes) ASSUME_YES=1; shift ;;
      *) break ;;
    esac
  done

  if (( $# == 0 )); then
    if [[ -t 0 ]]; then
      CMD="interactive"
      return 0
    else
      usage
      exit 0
    fi
  fi
  case "$1" in
    setup)
      CMD="setup"; shift ;;
    doctor)
      CMD="doctor"; shift ;;
    status|health)
      CMD="status"; shift ;;
    site)
      CMD="site"; shift
      if (( $# >= 1 )) && [[ $1 != -* ]]; then
        case "$1" in
          list|add|remove) SUBCMD="$1" ;;
          *) echo "Unknown site subcommand: $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
      else
        SUBCMD="list"
      fi
      ;;
    db)
      CMD="db"; shift
      if (( $# >= 1 )) && [[ $1 != -* ]]; then
        case "$1" in
          list|create|drop) SUBCMD="$1" ;;
          *) echo "Unknown db subcommand: $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
      else
        SUBCMD="list"
      fi
      ;;
    cloudflare)
      CMD="cloudflare"; shift ;;
    dokploy)
      CMD="dokploy"; shift
      if (( $# >= 1 )) && [[ $1 != -* ]]; then
        case "$1" in
          setup|status|update) SUBCMD="$1" ;;
          *) echo "Unknown dokploy subcommand: $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
      else
        SUBCMD="setup"
      fi
      ;;
    update)
      CMD="update"; shift ;;
    uninstall)
      CMD="uninstall"; shift ;;
    -h|--help|help)
      usage; exit 0 ;;
    -v|--version|version)
      echo "neo $VERSION"; exit 0 ;;
    -*)
      case "$1" in
        --doctor) CMD="doctor"; shift ;;
        --list-sites) CMD="site"; SUBCMD="list"; shift ;;
        --add-domain) CMD="site"; SUBCMD="add"; shift ;;
        --remove-domain)
          CMD="site"; SUBCMD="remove"; shift
          [[ $# -ge 1 ]] || die "--remove-domain needs a domain"
          CFG[arg_manage]=$1; shift
          ;;
        --list-databases) CMD="db"; SUBCMD="list"; shift ;;
        --add-database) CMD="db"; SUBCMD="create"; shift ;;
        --drop-database)
          CMD="db"; SUBCMD="drop"; shift
          [[ $# -ge 1 ]] || die "--drop-database needs a database name"
          CFG[arg_manage]=$1; shift
          ;;
        --update) CMD="update"; shift ;;
        --uninstall) CMD="uninstall"; shift ;;
        --preset|--dry-run|-y|--yes|--ssh-key|--webserver|--domain|--site-type|--port|--redirect-to|--app-cmd|--hsts|--no-workers|--engine|--db|--db-user|--purge-files|--keep-cert|--email)
          CMD="setup"
          ;;
        *)
          echo "Unknown option: $1" >&2
          usage >&2
          exit 2
          ;;
      esac
      ;;
    *)
      echo "Unknown command: $1" >&2
      usage >&2
      exit 2
      ;;
  esac

  while (( $# )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -v|--version) echo "neo $VERSION"; exit 0 ;;
      --dry-run) DRY_RUN=1 ;;
      -y|--yes) ASSUME_YES=1 ;;
      --preset) [[ $# -ge 2 ]] || die "--preset needs a value"; PRESET=$2; shift ;;
      --ssh-key) [[ $# -ge 2 ]] || die "--ssh-key needs a value"; CFG[ssh_pubkey]=$2; shift ;;
      --webserver)
        [[ $# -ge 2 ]] || die "--webserver needs a value"
        [[ $2 =~ ^(nginx|caddy|apache)$ ]] || die "--webserver must be nginx, caddy or apache"
        CFG[arg_webserver]=$2; shift ;;
      --email) [[ $# -ge 2 ]] || die "--email needs a value"; CFG[arg_email]=$2; shift ;;
      --domain) [[ $# -ge 2 ]] || die "--domain needs a value"; CFG[arg_domain]=$2; shift ;;
      --site-type) [[ $# -ge 2 ]] || die "--site-type needs a value"; CFG[arg_type]=$2; shift ;;
      --port) [[ $# -ge 2 ]] || die "--port needs a value"; CFG[arg_port]=$2; shift ;;
      --redirect-to) [[ $# -ge 2 ]] || die "--redirect-to needs a value"; CFG[arg_target]=$2; shift ;;
      --app-cmd) [[ $# -ge 2 ]] || die "--app-cmd needs a value"; CFG[arg_app_cmd]=$2; shift ;;
      --hsts) CFG[arg_hsts]=1 ;;
      --no-workers) CFG[arg_no_workers]=1 ;;
      --purge-files) CFG[arg_purge]=1 ;;
      --keep-cert) CFG[arg_keep_cert]=1 ;;
      --engine)
        [[ $# -ge 2 ]] || die "--engine needs a value"
        [[ $2 =~ ^(postgresql|mysql)$ ]] || die "--engine must be postgresql or mysql"
        CFG[arg_engine]=$2; shift ;;
      --db) [[ $# -ge 2 ]] || die "--db needs a value"; CFG[arg_db]=$2; shift ;;
      --db-user) [[ $# -ge 2 ]] || die "--db-user needs a value"; CFG[arg_db_user]=$2; shift ;;
      -*)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
      *)
        if [[ -z ${CFG[arg_manage]:-} ]]; then
          CFG[arg_manage]=$1
        else
          echo "Unexpected argument: $1" >&2
          usage >&2
          exit 2
        fi
        ;;
    esac
    shift
  done
}

# ------------------------------------------------------------------ preflight & locks
preflight_root() {
  [[ $CMD == doctor || $CMD == status ]] && return 0
  if [[ $CMD == site && $SUBCMD == list ]] || [[ $CMD == db && $SUBCMD == list ]] || [[ $CMD == dokploy && $SUBCMD == status ]]; then return 0; fi
  if (( EUID != 0 && DRY_RUN == 0 )); then die "$(t err.root)"; fi
}

acquire_lock() {
  (( DRY_RUN )) && return 0
  [[ $CMD == doctor || $CMD == status ]] && return 0
  if [[ $CMD == site && $SUBCMD == list ]] || [[ $CMD == db && $SUBCMD == list ]] || [[ $CMD == dokploy && $SUBCMD == status ]]; then return 0; fi
  command -v flock >/dev/null 2>&1 || return 0
  { exec 9>/run/neo.lock; } 2>/dev/null || return 0
  flock -n 9 || die "$(t err.locked)"
}

STATEF=""
cleanup_on_exit() { [[ -n $STATEF ]] && rm -f "$STATEF"; return 0; }
on_interrupt() { echo >&2; log_warn "$(t run.interrupted)"; exit 130; }

ensure_whiptail() {
  return 0
}

quit_cancel() { echo; log_info "$(t msg.cancelled)"; exit 130; }

check_os() {
  detect_os || die "$(t err.os_unsupported "unknown")"
  local rc=0
  os_check || rc=$?
  case $rc in
    2) die "$(t err.os_unsupported "$OS_PRETTY")" ;;
    1) ui_msg "$OS_PRETTY" "$(t warn.os_untested "$OS_PRETTY")" ;;
    3)
       if (( ASSUME_YES )); then
         log_warn "$(t warn.os_eol "$OS_PRETTY")"
       else
         ui_yesno "$OS_PRETTY" "$(t warn.os_eol "$OS_PRETTY")\n\n$(t warn.os_eol_ask)" no || quit_cancel
       fi ;;
  esac
}

load_modules() {
  local family=$OS_ID dir f
  case "$OS_ID" in
    almalinux|rocky|rhel|centos|ol|amzn|fedora) family=almalinux ;;
    debian) family=debian ;;
    *) family=ubuntu ;;
  esac
  dir="$ROOT_DIR/modules/$family"
  [[ -d $dir ]] || die "$(t err.os_unsupported "$OS_PRETTY")"
  for f in "$dir"/*.sh; do
    # shellcheck source=/dev/null
    source "$f"
  done
}

check_environment() {
  local title text
  if is_wsl; then
    title=$(t env.wsl.title); text=$(t env.wsl.text)
  elif ! has_systemd; then
    title=$(t env.nosystemd.title); text=$(t env.nosystemd.text)
  else
    return 0
  fi
  if (( ASSUME_YES )); then log_warn "$text"; return 0; fi
  ui_yesno "$title" "$text" no || quit_cancel
}

_fmt_help_section() {
  local heading=$1
  shift
  local out=""
  out+=$(printf '\033[1;36m==> %s\033[0m\n\033[2m──────────────────────────────────────────────────────────\033[0m\n' "$heading")
  out+=$'\n'
  local id
  for id in "$@"; do
    out+=$(printf '\033[1m• %s\033[0m (\033[36m%s\033[0m)\n  %s\n' "$(t "feat.$id.title")" "$id" "$(t "feat.$id.desc")")
    out+=$'\n'
  done
  printf '%b' "$out"
}

show_help() {
  local choice
  while true; do
    choice=$(ui_menu "📖 About Neo Options" "Select a category to explore" system \
      system      "🛡️  System & Security       (Updates, SSH, User, Swap, Firewall, Fail2ban)" \
      web         "🌐 Web Servers & Domains    (Nginx, Caddy, Apache, Certbot, Sites, Cloudflare)" \
      db          "🗄️  Databases               (PostgreSQL, MySQL, Redis, DB Wizard)" \
      containers  "📦 Containers & PaaS        (Docker, Podman, Dokploy PaaS)" \
      runtimes    "⚙️  Runtimes & Toolchains   (Node, Bun, Go, Python, PHP, FrankenPHP)" \
      ops         "📊 Ops & Monitoring         (Nightly DB Dumps, Health Audit, Nginx Jails)" \
      all         "📋 Complete Feature Guide  (All 29 features)" \
      back        "⬅️  Back to Menu") || return 0

    case "$choice" in
      system)
        ui_scroll "🛡️ System & Security" "$(_fmt_help_section "System, Access & Security" system_update timezone hostname swap create_user ssh_harden ufw fail2ban auto_updates)"
        ;;
      web)
        ui_scroll "🌐 Web Servers & Domains" "$(_fmt_help_section "Web Servers & Domains" webserver certbot add_domain cloudflare)"
        ;;
      db)
        ui_scroll "🗄️ Databases" "$(_fmt_help_section "Databases & Caching" postgresql mysql redis create_database)"
        ;;
      containers)
        ui_scroll "📦 Containers & PaaS" "$(_fmt_help_section "Containers & PaaS" docker_runtime podman_runtime dokploy)"
        ;;
      runtimes)
        ui_scroll "⚙️ Runtimes & Toolchains" "$(_fmt_help_section "Runtimes & Development Tools" node_runtime bun_runtime go_runtime python_runtime php_runtime frankenphp)"
        ;;
      ops)
        ui_scroll "📊 Ops & Monitoring" "$(_fmt_help_section "Ops, Monitoring & Reliability" db_backup monitoring nginx_jails)"
        ;;
      all)
        local all_text=""
        all_text+="$(_fmt_help_section "System, Access & Security" system_update timezone hostname swap create_user ssh_harden ufw fail2ban auto_updates)"$'\n'
        all_text+="$(_fmt_help_section "Web Servers & Domains" webserver certbot add_domain cloudflare)"$'\n'
        all_text+="$(_fmt_help_section "Databases & Caching" postgresql mysql redis create_database)"$'\n'
        all_text+="$(_fmt_help_section "Containers & PaaS" docker_runtime podman_runtime dokploy)"$'\n'
        all_text+="$(_fmt_help_section "Runtimes & Development Tools" node_runtime bun_runtime go_runtime python_runtime php_runtime frankenphp)"$'\n'
        all_text+="$(_fmt_help_section "Ops, Monitoring & Reliability" db_backup monitoring nginx_jails)"
        ui_scroll "📋 Complete Feature Guide" "$all_text"
        ;;
      back)
        return 0
        ;;
    esac
  done
}

welcome() {
  printf "\n  \033[1;36m/\\_/\\  \033[0m\n ( \033[1;33mo\033[0m.\033[1;33mo\033[0m )  \033[1;37mNeo\033[0m — \033[1;36mLinux Server Manager\033[0m\n  \033[1;36m> ^ <\033[0m   \033[2mCalm, sturdy, and keeping your VPS purr-fect.\033[0m\n"
  ui_msg "$(t welcome.title)" "$(t welcome.text "$OS_PRETTY" "$MEM_MB" "$CPU_COUNT" "$LOG_FILE")"
}

site_hub_menu() {
  local c d
  while true; do
    c=$(ui_menu "🌐 Websites" "Manage virtual hosts & SSL" list \
      list   "📋 List websites" \
      add    "➕ Add new website (wizard)" \
      remove "🗑️  Remove website" \
      back   "⬅️  Back to Hub") || return 0
    case $c in
      list)
        list_sites
        read -r -p "$(t menu.manage.press_enter)" _ || true
        ;;
      add)
        PRESET=domain
        load_preset "domain"
        SELECTED_SET=()
        for id in "${!PRESET_SET[@]}"; do SELECTED_SET[$id]=1; done
        prompt_features
        review
        run_features
        summary
        return 0
        ;;
      remove)
        d=$(ui_input "$(t manage.confirm_site_title)" "$(t menu.manage.ask_remove_domain)" "") || continue
        [[ -n $d ]] || continue
        remove_domain "$d"
        read -r -p "$(t menu.manage.press_enter)" _ || true
        ;;
      back)
        return 0
        ;;
    esac
  done
}

db_hub_menu() {
  local c n
  while true; do
    c=$(ui_menu "🗄️ Databases" "Manage database engines & users" list \
      list   "📋 List databases" \
      create "➕ Create database & user" \
      drop   "🗑️  Drop database (auto-dumps first)" \
      back   "⬅️  Back to Hub") || return 0
    case $c in
      list)
        list_databases
        read -r -p "$(t menu.manage.press_enter)" _ || true
        ;;
      create)
        PRESET=database
        load_preset "database"
        SELECTED_SET=()
        for id in "${!PRESET_SET[@]}"; do SELECTED_SET[$id]=1; done
        prompt_features
        review
        run_features
        summary
        return 0
        ;;
      drop)
        n=$(ui_input "$(t manage.db_confirm_title)" "$(t menu.manage.ask_drop_database)" "") || continue
        [[ -n $n ]] || continue
        drop_database "$n"
        read -r -p "$(t menu.manage.press_enter)" _ || true
        ;;
      back)
        return 0
        ;;
    esac
  done
}

dokploy_hub_menu() {
  local c
  while true; do
    c=$(ui_menu "🚀 Dokploy PaaS" "Manage Dokploy on Docker Swarm" status \
      status "📊 Inspect Dokploy services" \
      setup  "🛠️  Deploy Dokploy stack (port 3000)" \
      update "🔄 Update Dokploy container" \
      back   "⬅️  Back to Hub") || return 0
    case $c in
      status)
        echo "== Dokploy Services =="
        if command -v docker >/dev/null 2>&1; then
          docker service ls --filter "name=dokploy" 2>/dev/null || true
          docker ps --filter "name=dokploy" 2>/dev/null || true
        else
          echo "Docker is not installed."
        fi
        read -r -p "$(t menu.manage.press_enter)" _ || true
        ;;
      setup)
        PRESET=dokploy
        load_preset "dokploy"
        SELECTED_SET=()
        for id in "${!PRESET_SET[@]}"; do SELECTED_SET[$id]=1; done
        prompt_features
        review
        run_features
        summary
        return 0
        ;;
      update)
        if (( DRY_RUN )); then
          log_dry "curl -sSL https://dokploy.com/install.sh | sh -s update"
        else
          run_sh "curl -sSL https://dokploy.com/install.sh | sh -s update"
        fi
        read -r -p "$(t menu.manage.press_enter)" _ || true
        ;;
      back)
        return 0
        ;;
    esac
  done
}

hub_menu() {
  printf "\n  \033[1;36m/\\_/\\  \033[0m\n ( \033[1;33mo\033[0m.\033[1;33mo\033[0m )  \033[1;37mNeo\033[0m — \033[1;36mLinux Server Manager\033[0m\n  \033[1;36m> ^ <\033[0m   \033[2mCalm, sturdy, and keeping your VPS purr-fect.\033[0m\n"
  local choice
  while true; do
    choice=$(ui_menu "🐱 Neo Hub" "Server management and control center" doctor \
      doctor         "🩺 Server Doctor       (Health & security audit)" \
      status         "📊 Server Status       (Live CPU, RAM, disk & services)" \
      sites          "🌐 Websites            (List, add, or remove sites)" \
      databases      "🗄️  Databases           (PostgreSQL, MySQL / MariaDB)" \
      dokploy        "🚀 Dokploy PaaS        (Deploy, inspect, or update Dokploy)" \
      setup          "🛠️  Server Setup        (Fresh VPS provisioning wizard)" \
      cloudflare     "☁️  Cloudflare          (Restore real visitor IPs)" \
      update         "🔄 Update Neo          (Check for latest release)" \
      uninstall      "🗑️  Uninstall           (Safely roll back Neo configs)" \
      quit           "🚪 Quit") || quit_cancel
    case $choice in
      doctor)
        neo_doctor
        read -r -p "$(t menu.manage.press_enter)" _ || true
        ;;
      status)
        neo_status
        read -r -p "$(t menu.manage.press_enter)" _ || true
        ;;
      sites)
        site_hub_menu
        ;;
      databases)
        db_hub_menu
        ;;
      dokploy)
        dokploy_hub_menu
        ;;
      setup)
        interactive_setup
        return 0
        ;;
      cloudflare)
        PRESET=cloudflare
        load_preset "cloudflare"
        SELECTED_SET=()
        for id in "${!PRESET_SET[@]}"; do SELECTED_SET[$id]=1; done
        prompt_features
        review
        run_features
        summary
        return 0
        ;;
      update)
        self_update
        read -r -p "$(t menu.manage.press_enter)" _ || true
        ;;
      uninstall)
        bash "$ROOT_DIR/lib/uninstall.sh"
        return 0
        ;;
      quit)
        quit_cancel
        ;;
    esac
  done
}

interactive_setup() {
  welcome
  select_preset
  select_features
  prompt_features
  review
  run_features
  summary
}

select_preset() {
  local choice
  [[ -n $PRESET ]] && return 0
  while true; do
    choice=$(ui_menu "$(t menu.main.title)" "$(t menu.main.text)" recommended \
      recommended "$(t menu.recommended)" \
      minimal "$(t menu.minimal)" \
      custom "$(t menu.custom)" \
      dokploy "Dokploy PaaS (Traefik + Docker Swarm)" \
      domain "$(t menu.domain)" \
      database "$(t menu.database)" \
      cloudflare "$(t menu.cloudflare)" \
      manage "$(t menu.manage)" \
      help "$(t menu.help)" \
      quit "$(t menu.quit)") || quit_cancel
    case $choice in
      manage) manage_menu ;;
      help) show_help ;;
      quit) quit_cancel ;;
      *) PRESET=$choice; return 0 ;;
    esac
  done
}

load_preset() {
  local name=$1 f="$ROOT_DIR/presets/$1.list" id
  PRESET_SET=()
  if [[ $name == custom ]]; then
    for id in "${FEATURE_IDS[@]}"; do
      [[ ${FEATURE_DEFAULT[$id]} == on ]] && PRESET_SET[$id]=1
    done
    return 0
  fi
  [[ -f $f ]] || die "$(t err.no_preset "$name")"
  while IFS= read -r id || [[ -n $id ]]; do
    id=${id%%#*}; id=${id//[[:space:]]/}
    [[ -n $id ]] && PRESET_SET[$id]=1
  done <"$f"
}

select_features() {
  local id state chosen
  local -a args=()
  load_preset "$PRESET"
  for id in "${FEATURE_IDS[@]}"; do
    state=off
    [[ -n ${PRESET_SET[$id]:-} ]] && state=on
    args+=("$id" "$(t "feat.$id.title")" "$state")
  done
  chosen=$(ui_checklist "$(t select.title)" "$(t select.text)" "${args[@]}") || quit_cancel
  SELECTED_SET=()
  for id in $chosen; do SELECTED_SET[$id]=1; done
  if (( ${#SELECTED_SET[@]} == 0 )); then log_info "$(t select.none)"; exit 0; fi
}

prompt_features() {
  local id dropped=""
  for id in "${FEATURE_IDS[@]}"; do
    feature_selected "$id" || continue
    declare -F "prompt_$id" >/dev/null || continue
    if ! "prompt_$id"; then
      log_warn "$(t prompt.skipped "$(t "feat.$id.title")")"
      dropped+="  - $(t "feat.$id.title")"$'\n'
      unset "SELECTED_SET[$id]"
    fi
  done
  if [[ -n $dropped ]] && (( ! ASSUME_YES )); then
    ui_msg "$(t prompt.dropped.title)" "$(t prompt.dropped.text "$dropped")"
  fi
  if (( ${#SELECTED_SET[@]} == 0 )); then log_info "$(t select.none)"; exit 0; fi
}

review() {
  local id text n=0 line
  text="$(t review.head)"$'\n\n'
  (( DRY_RUN )) && text+="$(t review.dry)"$'\n\n'
  for id in "${FEATURE_IDS[@]}"; do
    feature_selected "$id" || continue
    n=$((n + 1))
    text+="$n. $(t "feat.$id.title")"$'\n'
    if declare -F "summary_$id" >/dev/null; then
      line=$("summary_$id")
      text+="     $line"$'\n'
    fi
  done
  text+=$'\n'"$(t review.ask)"
  ui_yesno "$(t review.title)" "$text" yes || quit_cancel
}

run_features() {
  local id title i=0 total=0 rc statef
  for id in "${FEATURE_IDS[@]}"; do feature_selected "$id" && total=$((total + 1)); done
  (( DRY_RUN )) && log_dry "no changes will be made"

  for id in "${FEATURE_IDS[@]}"; do
    feature_selected "$id" || continue
    i=$((i + 1))
    title=$(t "feat.$id.title")
    log_step "[$i/$total] $title"
    rc=0
    statef=$(mktemp); STATEF=$statef
    ( set -e
      # shellcheck disable=SC2064
      trap "declare -p CFG >\"$statef\" 2>/dev/null" EXIT
      "run_$id" )
    rc=$?
    if [[ -s $statef ]]; then
      # shellcheck disable=SC1090
      source <(sed '1s/^declare -A/declare -gA/' "$statef")
    fi
    rm -f "$statef"; STATEF=""
    case $rc in
      0)  RESULT[$id]=ok; state_mark "$id" ok; printf '🐱  %s\n' "$title" ;;
      10) RESULT[$id]=skipped; state_mark "$id" skipped ;;
      *)  RESULT[$id]=failed; state_mark "$id" failed; log_err "$title: $(t run.failed)" ;;
    esac
  done
}

summary() {
  local id status mark notes="" out
  log_step "$(t summary.title)"
  printf '🐱  %sNeo setup complete.%s\n\n' "$C_BOLD" "$C_RESET"
  for id in "${FEATURE_IDS[@]}"; do
    feature_selected "$id" || continue
    status=${RESULT[$id]:-skipped}
    case $status in
      ok)      mark="${C_GREEN}✓${C_RESET} $(t summary.ok)" ;;
      skipped) mark="${C_YELLOW}–${C_RESET} $(t summary.skipped)" ;;
      failed)  mark="${C_RED}✗${C_RESET} $(t summary.failed)" ;;
    esac
    printf '  %s  %s\n' "$mark" "$(t "feat.$id.title")"
    if [[ $status == ok ]] && declare -F "notes_$id" >/dev/null; then
      out=$("notes_$id" 2>/dev/null || true)
      [[ -n $out ]] && notes+="$out"$'\n'
    fi
  done

  if [[ -n $notes || -f /var/run/reboot-required ]]; then
    printf '\n%s%s%s\n' "$C_BOLD" "$(t summary.next)" "$C_RESET"
    [[ -n $notes ]] && printf '%s' "$notes" | sed 's/^/  /'
    [[ -f /var/run/reboot-required ]] && printf '  %s\n' "$(t note.reboot)"
  fi
  printf '\n%s\n' "$(t summary.log "$LOG_FILE")"
  (( DRY_RUN )) && printf '%s\n' "$(t summary.dry)"

  for id in "${!RESULT[@]}"; do [[ ${RESULT[$id]} == failed ]] && return 1; done
  return 0
}

self_update() {
  local repo=${NEO_REPO:-parxyws/neo} ref=${NEO_REF:-main}
  if [[ -d $ROOT_DIR/.git ]] && command -v git >/dev/null 2>&1; then
    log_info "$(t update.git "$ROOT_DIR")"
    if (( DRY_RUN )); then log_dry "git -C $ROOT_DIR pull --ff-only"; return 0; fi
    git -C "$ROOT_DIR" pull --ff-only || { log_err "$(t update.failed)"; return 1; }
  else
    log_info "$(t update.download "$repo@$ref" "$ROOT_DIR")"
    if (( DRY_RUN )); then log_dry "install.sh from $repo@$ref into $ROOT_DIR"; return 0; fi
    curl -fsSL "https://raw.githubusercontent.com/$repo/$ref/install.sh" \
      | NEO_DIR="$ROOT_DIR" NEO_REF="$ref" NEO_REPO="$repo" NEO_NO_RUN=1 bash \
      || { log_err "$(t update.failed)"; return 1; }
  fi
  log_ok "$(t update.done "$(bash "$ROOT_DIR/neo.sh" --version 2>/dev/null)")"
}

# ------------------------------------------------------------------ subcommand execution
execute_cmd() {
  preflight_root
  trap cleanup_on_exit EXIT
  trap on_interrupt INT TERM
  acquire_lock

  case "$CMD" in
    interactive)
      ensure_whiptail
      ui_init
      check_os
      load_modules
      detect_hw
      check_environment
      hub_menu
      ;;
    setup)
      if (( ASSUME_YES )) && [[ -z $PRESET ]]; then die "$(t err.yes_preset)"; fi
      ensure_whiptail
      ui_init
      check_os
      load_modules
      detect_hw
      check_environment
      if [[ -z $PRESET ]]; then
        interactive_setup
      else
        load_preset "$PRESET"
        SELECTED_SET=()
        for id in "${!PRESET_SET[@]}"; do SELECTED_SET[$id]=1; done
        prompt_features
        (( ! ASSUME_YES )) && review
        run_features
        summary
      fi
      ;;
    doctor)
      neo_doctor
      ;;
    status)
      neo_status
      ;;
    cloudflare)
      PRESET=cloudflare
      ensure_whiptail
      ui_init
      check_os
      load_modules
      detect_hw
      load_preset "cloudflare"
      SELECTED_SET=()
      for id in "${!PRESET_SET[@]}"; do SELECTED_SET[$id]=1; done
      prompt_features
      (( ! ASSUME_YES )) && review
      run_features
      summary
      ;;
    site)
      detect_os 2>/dev/null || true
      load_modules
      detect_hw
      case "$SUBCMD" in
        list)
          list_sites
          ;;
        add)
          PRESET=domain
          ensure_whiptail
          ui_init
          check_os
          load_preset "domain"
          SELECTED_SET=()
          for id in "${!PRESET_SET[@]}"; do SELECTED_SET[$id]=1; done
          prompt_features
          (( ! ASSUME_YES )) && review
          run_features
          summary
          ;;
        remove)
          local target=${CFG[arg_manage]:-}
          if [[ -z $target ]]; then
            if (( ASSUME_YES )); then die "site remove requires a domain name"; fi
            ensure_whiptail
            ui_init
            target=$(ui_input "$(t manage.confirm_site_title)" "$(t menu.manage.ask_remove_domain)" "") || exit 0
          fi
          [[ -n $target ]] || exit 0
          remove_domain "$target"
          ;;
        *)
          echo "Unknown site subcommand: $SUBCMD" >&2
          usage >&2
          exit 2
          ;;
      esac
      ;;
    db)
      detect_os 2>/dev/null || true
      load_modules
      detect_hw
      case "$SUBCMD" in
        list)
          list_databases
          ;;
        create)
          PRESET=database
          ensure_whiptail
          ui_init
          check_os
          load_preset "database"
          SELECTED_SET=()
          for id in "${!PRESET_SET[@]}"; do SELECTED_SET[$id]=1; done
          prompt_features
          (( ! ASSUME_YES )) && review
          run_features
          summary
          ;;
        drop)
          local target=${CFG[arg_manage]:-}
          if [[ -z $target ]]; then
            if (( ASSUME_YES )); then die "db drop requires a database name"; fi
            ensure_whiptail
            ui_init
            target=$(ui_input "$(t manage.db_confirm_title)" "$(t menu.manage.ask_drop_database)" "") || exit 0
          fi
          [[ -n $target ]] || exit 0
          drop_database "$target"
          ;;
        *)
          echo "Unknown db subcommand: $SUBCMD" >&2
          usage >&2
          exit 2
          ;;
      esac
      ;;
    dokploy)
      case "$SUBCMD" in
        setup)
          PRESET=dokploy
          ensure_whiptail
          ui_init
          check_os
          load_modules
          detect_hw
          load_preset "dokploy"
          SELECTED_SET=()
          for id in "${!PRESET_SET[@]}"; do SELECTED_SET[$id]=1; done
          prompt_features
          (( ! ASSUME_YES )) && review
          run_features
          summary
          ;;
        status)
          echo "== Dokploy Services =="
          if command -v docker >/dev/null 2>&1; then
            docker service ls --filter "name=dokploy" 2>/dev/null || true
            docker ps --filter "name=dokploy" 2>/dev/null || true
          else
            echo "Docker is not installed."
          fi
          ;;
        update)
          echo "Updating Dokploy..."
          if (( DRY_RUN )); then
            log_dry "curl -sSL https://dokploy.com/install.sh | sh -s update"
          else
            run_sh "curl -sSL https://dokploy.com/install.sh | sh -s update"
          fi
          ;;
      esac
      ;;
    update)
      self_update
      ;;
    uninstall)
      local -a uargs=()
      (( ASSUME_YES )) && uargs+=(--yes)
      (( DRY_RUN )) && uargs+=(--dry-run)
      exec bash "$ROOT_DIR/lib/uninstall.sh" "${uargs[@]}"
      ;;
  esac
}

main() {
  parse_args "$@"
  execute_cmd
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
