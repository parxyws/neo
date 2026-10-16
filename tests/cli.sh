#!/usr/bin/env bash
# CLI routing and subcommand parser tests.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
export PATH="/opt/homebrew/bin:$PATH"

fail=0
ok()  { "$@" || { echo "FAIL (expected 0): $*"; fail=1; }; }
expect_code() {
  local expected=$1
  shift
  local code=0
  "$@" >/dev/null 2>&1 || code=$?
  if (( code != expected )); then
    echo "FAIL (expected exit code $expected, got $code): $*"
    fail=1
  fi
}

# Help and version routes
ok ./neo.sh --help
ok ./neo.sh -h
ok ./neo.sh -v
ok ./neo.sh --version

# Read-only routes without root
./neo.sh doctor --dry-run >/dev/null 2>&1 || [[ $? -eq 1 ]] || { echo "FAIL: doctor returned unexpected exit code"; fail=1; }
expect_code 2 ./neo.sh invalid-command
expect_code 2 ./neo.sh --invalid-flag
expect_code 2 ./neo.sh site invalid-subcmd
expect_code 2 ./neo.sh db invalid-subcmd
expect_code 2 ./neo.sh dokploy invalid-subcmd

ok ./neo.sh site list
ok ./neo.sh db list
ok ./neo.sh dokploy status
ok ./neo.sh dokploy update --dry-run
ok ./neo.sh setup --preset dokploy --dry-run --yes --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl test@example"

# Flag requiring preset
expect_code 1 ./neo.sh setup --dry-run --yes

(( fail )) && echo "CLI TESTS FAILED" || echo "cli tests passed"
exit $fail
