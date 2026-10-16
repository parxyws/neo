#!/usr/bin/env bash
# Smoke tests: syntax, message-key coverage, and full non-interactive dry runs.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
export PATH="/opt/homebrew/bin:$PATH"

fail=0

echo "== syntax =="
for f in neo.sh install.sh lib/*.sh modules/*/*.sh tests/*.sh; do
  bash -n "$f" || { echo "SYNTAX ERROR: $f"; fail=1; }
done

echo "== message keys used but not defined in lib/messages.sh =="
used=$(grep -rhoE '\bt "?[a-z0-9_]+\.[a-z0-9_.]+' neo.sh lib modules | sed -E 's/^t "?//' | grep -v '\.$' | sort -u)
for k in $used; do
  grep -qF "MSG[$k]=" lib/messages.sh || { echo "MISSING KEY: $k"; fail=1; }
done

echo "== dry run: recommended =="
./neo.sh setup --yes --dry-run --preset recommended --ssh-key \
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl test@example" \
  >/tmp/neo-dry.out 2>&1 || { echo "dry run FAILED"; tail -n 30 /tmp/neo-dry.out; fail=1; }

# Regression check: preset features must not be dropped silently
grep -q "Nginx fail2ban jails" /tmp/neo-dry.out && ! grep -q "^! Skipped:" /tmp/neo-dry.out \
  || { echo "REGRESSION: a selected feature was dropped"; grep "Skipped" /tmp/neo-dry.out; fail=1; }

echo "== CFG survives feature subshell =="
fam="ubuntu"
ztest=modules/$fam/99-ztest.sh
cat > "$ztest" <<'EOT'
register_feature ztest test on
run_ztest() { CFG[ztest_out]=from-subshell; }
notes_ztest() { echo "ZTEST_VALUE=${CFG[ztest_out]:-missing}"; }
EOT
echo ztest > presets/_z.list
./neo.sh setup --yes --dry-run --preset _z >/tmp/neo-dry-z.out 2>&1
grep -q "ZTEST_VALUE=from-subshell" /tmp/neo-dry-z.out \
  || { echo "REGRESSION: CFG lost after run_<feature>"; fail=1; }
rm -f "$ztest" presets/_z.list

echo "== dry run: minimal =="
./neo.sh setup --yes --dry-run --preset minimal >/tmp/neo-dry2.out 2>&1 \
  || { echo "dry run FAILED: minimal"; tail -n 15 /tmp/neo-dry2.out; fail=1; }

echo "== uninstall --dry-run =="
./neo.sh uninstall --dry-run >/tmp/neo-uninst.out 2>&1 \
  && grep -q "Rollback complete" /tmp/neo-uninst.out \
  && ! grep -q "^  removed: " /tmp/neo-uninst.out \
  || { echo "uninstall dry run FAILED"; tail -n 15 /tmp/neo-uninst.out; fail=1; }

printf 'webserver\nadd_domain\n' > presets/_wd.list
printf 'webserver\ncloudflare\n' > presets/_cf.list
trap 'rm -f presets/_wd.list presets/_cf.list' EXIT

echo "== dry run: every web server x site type =="
for ws in nginx apache caddy; do
  for ty in static spa proxy laravel php wordpress redirect; do
    ./neo.sh setup --yes --dry-run --preset _wd --webserver "$ws" --email me@example.com \
      --domain "t-$ty.example.com" --site-type "$ty" --port 3000 --redirect-to https://example.org \
      >/tmp/neo-dry3.out 2>&1 || { echo "dry run FAILED: $ws/$ty"; tail -n 15 /tmp/neo-dry3.out; fail=1; }
  done
done

echo "== dry run: app service (proxy --app-cmd), Laravel workers, --no-workers =="
./neo.sh setup --yes --dry-run --preset _wd --webserver nginx --domain app.example.com \
  --site-type proxy --port 3000 --app-cmd 'npm start' --hsts >/tmp/neo-dry5.out 2>&1 \
  && grep -q "write /etc/systemd/system/app-app.example.com.service" /tmp/neo-dry5.out \
  && grep -q "systemctl enable app-app.example.com.service" /tmp/neo-dry5.out \
  || { echo "dry run FAILED: proxy --app-cmd"; tail -n 15 /tmp/neo-dry5.out; fail=1; }

./neo.sh setup --yes --dry-run --preset _wd --webserver nginx --domain lv.example.com \
  --site-type laravel >/tmp/neo-dry5.out 2>&1 \
  && grep -q "enable --now laravel-lv.example.com-queue.service laravel-lv.example.com-schedule.timer" /tmp/neo-dry5.out \
  || { echo "dry run FAILED: laravel workers"; tail -n 15 /tmp/neo-dry5.out; fail=1; }

./neo.sh setup --yes --dry-run --preset _wd --webserver nginx --domain lv.example.com \
  --site-type laravel --no-workers >/tmp/neo-dry5.out 2>&1 && ! grep -q "laravel-lv" /tmp/neo-dry5.out \
  || { echo "dry run FAILED: laravel --no-workers"; tail -n 15 /tmp/neo-dry5.out; fail=1; }

./neo.sh setup --yes --dry-run --preset _wd --webserver nginx --domain bad.example.com \
  --site-type proxy --app-cmd "echo 'x'" >/tmp/neo-dry5.out 2>&1
grep -q "single quotes" /tmp/neo-dry5.out && ! grep -q "app-bad.example.com" /tmp/neo-dry5.out \
  || { echo "REGRESSION: an --app-cmd with single quotes must be refused"; tail -n 10 /tmp/neo-dry5.out; fail=1; }

echo "== dry run: Cloudflare real IP (nginx, apache; caddy must be refused) =="
for ws in nginx apache; do
  ./neo.sh setup --yes --dry-run --preset _cf --webserver "$ws" --email me@example.com >/tmp/neo-dry4.out 2>&1 \
    && grep -q "neo-cloudflare-ips --server $ws" /tmp/neo-dry4.out \
    || { echo "dry run FAILED: cloudflare on $ws"; tail -n 15 /tmp/neo-dry4.out; fail=1; }
done
./neo.sh setup --yes --dry-run --preset _cf --webserver caddy --email me@example.com >/tmp/neo-dry4.out 2>&1
grep -q "Cloudflare support needs Nginx or Apache" /tmp/neo-dry4.out && grep -q "Skipped: Cloudflare" /tmp/neo-dry4.out \
  || { echo "REGRESSION: cloudflare + caddy should be refused with an explanation"; tail -n 10 /tmp/neo-dry4.out; fail=1; }

(( fail )) && echo "DRY-RUN TESTS FAILED" || echo "dry-run tests passed"
exit $fail
