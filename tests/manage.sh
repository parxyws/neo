#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC2317,SC2329
# Tests for lib/manage.sh: list / remove websites, list / drop databases.
# Hermetic: every /etc and /var/www path is redirected into a temp dir (NEO_ROOT) and every
# system command (nginx, certbot, systemctl, psql, mysql, ...) is a stub.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
export PATH="/opt/homebrew/bin:$PATH"

fail=0
pass() { echo "  ok   $*"; }
bad()  { echo "  FAIL $*"; fail=1; }
check()  { local d=$1; shift; if "$@"; then pass "$d"; else bad "$d"; fi; }
reject() { local d=$1; shift; if "$@"; then bad "$d"; else pass "$d"; fi; }
exists() { [[ -e $1 || -L $1 ]]; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export NEO_ROOT=$T/root LOG_FILE=$T/neo.log
R=$NEO_ROOT
mkdir -p "$R" "$T/bin"
export STUB_LOG=$T/stub.log STUB_FAIL_DIR=$T/fail
mkdir -p "$STUB_FAIL_DIR"
: >"$STUB_LOG"

# ------------------------------------------------------------------ stubs
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$T/bin/$1"; chmod +x "$T/bin/$1"; }
mkstub nginx     'echo "nginx $*" >>"$STUB_LOG"; [ -e "$STUB_FAIL_DIR/nginx" ] && exit 1; exit 0'
mkstub apachectl 'echo "apachectl $*" >>"$STUB_LOG"; exit 0'
mkstub httpd     'echo "httpd $*" >>"$STUB_LOG"; exit 0'
mkstub caddy     'echo "caddy $*" >>"$STUB_LOG"; exit 0'
mkstub systemctl 'echo "systemctl $*" >>"$STUB_LOG"; exit 0'
mkstub certbot   'echo "certbot $*" >>"$STUB_LOG"; [ "$1" = delete ] && rm -rf "$NEO_ROOT/etc/letsencrypt/live/$3"; exit 0'
mkstub runuser   'shift 3; exec "$@"'
mkstub psql 'echo "psql $*" >>"$STUB_LOG"
case "$*" in
  *"FROM pg_database d JOIN"*) printf "app1 owner1\napp2 owner2\n" ;;
  *"SELECT 1 FROM pg_database"*) case "$*" in *app1*) echo 1 ;; esac ;;
  *"DROP DATABASE"*) [ -e "$STUB_FAIL_DIR/drop" ] && exit 1 ;;
esac
exit 0'
mkstub pg_dump 'echo "pg_dump $*" >>"$STUB_LOG"; [ -e "$STUB_FAIL_DIR/dump" ] && exit 1; echo "-- dump of $1"'
mkstub mysql 'echo "mysql $*" >>"$STUB_LOG"
case "$*" in
  *"SHOW DATABASES"*) printf "information_schema\nmysql\nperformance_schema\nshop\nsys\n" ;;
  *"information_schema.SCHEMATA"*) case "$*" in *shop*) echo shop ;; esac ;;
esac
exit 0'
mkstub mysqldump 'echo "mysqldump $*" >>"$STUB_LOG"; [ -e "$STUB_FAIL_DIR/dump" ] && exit 1; echo "-- mysqldump of $4"'
export PATH="$T/bin:$PATH"

# shellcheck source=../neo.sh
source ./neo.sh
DRY_RUN=0; ASSUME_YES=1
BACKUP_DIR=$T/backup
OS_ID=ubuntu; OS_VERSION=24.04
load_modules

logged() { grep -qF -- "$1" "$STUB_LOG"; }
clear_log() { : >"$STUB_LOG"; }

mk_nginx_site() {
  local d=$1
  mkdir -p "$R/etc/nginx/sites-available" "$R/etc/nginx/sites-enabled" "$R/etc/letsencrypt/live/$d" "$R/var/www/$d/public"
  printf '# Managed by neo — %s\nserver { server_name %s; }\n' "${2:-static website}" "$d" >"$R/etc/nginx/sites-available/$d.conf"
  ln -sfn "../sites-available/$d.conf" "$R/etc/nginx/sites-enabled/$d.conf"
  echo hello >"$R/var/www/$d/public/index.html"
}

# ================================================================== list sites
echo "== list sites =="
mk_nginx_site a.example.com
mk_nginx_site b.example.com "reverse proxy"
printf 'server { server_name other.example.com; }\n' >"$R/etc/nginx/sites-available/other.example.com.conf"
printf '# Managed by neo — catch-all\nserver { }\n' >"$R/etc/nginx/sites-available/00-default.conf"
out=$(list_sites)
check "managed sites are listed"                    grep -q '^a.example.com .*nginx' <<<"$out"
check "type and https are shown"                    grep -q '^b.example.com .*reverse proxy .*yes' <<<"$out"
reject "a config without the marker is not listed"  grep -q 'other.example.com' <<<"$out"
reject "the catch-all is not listed as a site"      grep -q '00-default' <<<"$out"
rm "$R/etc/nginx/sites-enabled/b.example.com.conf"
check "a disabled site is flagged"                  grep -q '^b.example.com .*disabled' <<<"$(list_sites)"
ln -sfn "../sites-available/b.example.com.conf" "$R/etc/nginx/sites-enabled/b.example.com.conf"

# ================================================================== remove a site
echo "== remove a site =="
reject "invalid domain refused"                     remove_domain 'a b;rm'
reject "unknown domain refused"                     remove_domain nope.example.com
reject "a config we did not create is refused"      remove_domain other.example.com
check  "...and it is still there"                   exists "$R/etc/nginx/sites-available/other.example.com.conf"

CFG=(); clear_log
check  "remove a.example.com"                       remove_domain a.example.com
reject "site config removed"                        exists "$R/etc/nginx/sites-available/a.example.com.conf"
reject "enabled link removed"                       exists "$R/etc/nginx/sites-enabled/a.example.com.conf"
check  "config was tested and reloaded"             logged "nginx -t"
check  "certificate deleted through certbot"        logged "certbot delete --cert-name a.example.com --non-interactive"
reject "certificate directory gone"                 exists "$R/etc/letsencrypt/live/a.example.com"
check  "site files are kept by default"             exists "$R/var/www/a.example.com/public/index.html"
check  "a copy of the config is in the backup dir"  bash -c "ls '$BACKUP_DIR' | grep -q 'a.example.com.conf'"
check  "other sites untouched"                      exists "$R/etc/nginx/sites-available/b.example.com.conf"
check  "the catch-all is untouched"                 exists "$R/etc/nginx/sites-available/00-default.conf"

echo "== --purge-files moves, never deletes =="
mk_nginx_site c.example.com; CFG=([arg_purge]=1); clear_log
check  "remove c.example.com --purge-files"         remove_domain c.example.com
reject "site folder gone from /var/www"             exists "$R/var/www/c.example.com"
check  "...and its content sits in the backup dir"  bash -c "cat '$BACKUP_DIR'/removed-sites/c.example.com.*/public/index.html | grep -q hello"

echo "== services of the site are removed with it =="
mk_nginx_site s.example.com "reverse proxy"; CFG=(); clear_log
mkdir -p "$R/etc/systemd/system"
for u in app-s.example.com.service laravel-s.example.com-schedule.timer; do
  printf '# Managed by neo — test\n[Unit]\n' >"$R/etc/systemd/system/$u"
done
printf '[Unit]\n' >"$R/etc/systemd/system/laravel-s.example.com-queue.service"
check  "remove s.example.com"                       remove_domain s.example.com
reject "app service file removed"                   exists "$R/etc/systemd/system/app-s.example.com.service"
reject "scheduler timer removed"                    exists "$R/etc/systemd/system/laravel-s.example.com-schedule.timer"
check  "app service was stopped and disabled"       logged "systemctl disable --now app-s.example.com.service"
check  "a unit without the marker is kept"          exists "$R/etc/systemd/system/laravel-s.example.com-queue.service"

echo "== rollback when web server rejects removal =="
mk_nginx_site rb.example.com; touch "$STUB_FAIL_DIR/nginx"; CFG=(); clear_log
reject "remove fails when nginx -t fails"           remove_domain rb.example.com
check  "config restored on failure"                 exists "$R/etc/nginx/sites-available/rb.example.com.conf"
check  "enabled link restored"                      exists "$R/etc/nginx/sites-enabled/rb.example.com.conf"
check  "certificate untouched on rollback"          exists "$R/etc/letsencrypt/live/rb.example.com"
check  "site files untouched"                       exists "$R/var/www/rb.example.com/public/index.html"
rm -f "$STUB_FAIL_DIR/nginx"

# ================================================================== databases
echo "== list databases =="
clear_log
out=$(list_databases)
check "PostgreSQL databases listed"                 grep -q 'app1' <<<"$out"
check "MySQL databases listed"                      grep -q 'shop' <<<"$out"
reject "system databases filtered out"              grep -q 'performance_schema' <<<"$out"

echo "== drop database: dump first, drop only on success =="
clear_log; CFG=([arg_engine]=postgresql)
check  "drop app1 (dump + drop)"                    drop_database app1
check  "pg_dump was run"                            logged "pg_dump app1"
check  "DROP DATABASE was run"                      logged 'DROP DATABASE "app1"'
check  "a compressed dump sits in the backup dir"   bash -c "ls '$BACKUP_DIR'/dropped-databases/app1.postgresql.*.sql.gz"

echo "== drop database fails safely when dump fails =="
touch "$STUB_FAIL_DIR/dump"; clear_log; CFG=([arg_engine]=postgresql)
reject "drop fails when dump fails"                 drop_database app1
reject "DROP DATABASE was NOT run"                  logged "DROP DATABASE"
rm -f "$STUB_FAIL_DIR/dump"

(( fail )) && echo "MANAGE TESTS FAILED" || echo "manage tests passed"
exit $fail
