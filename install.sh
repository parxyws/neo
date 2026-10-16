#!/usr/bin/env bash
# =============================================================================
# Neo bootstrap installer — downloads Neo and launches setup.
#
#   curl -fsSL https://raw.githubusercontent.com/parxyws/neo/main/install.sh | sudo bash
#
# Pin a release with NEO_REF (a release tag like v1.0.0 or commit SHA):
#   curl -fsSL .../install.sh | sudo NEO_REF=v1.0.0 bash
# Optionally verify checksum: NEO_SHA256=<sha256>
# NEO_NO_RUN=1 only installs or updates without running setup immediately.
# =============================================================================
set -euo pipefail

REPO="${NEO_REPO:-parxyws/neo}"
REF="${NEO_REF:-main}"
DEST="${NEO_DIR:-/opt/neo}"
SHA256="${NEO_SHA256:-}"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root, e.g.: curl -fsSL <url> | sudo bash" >&2
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  PKG_UPDATE=(env DEBIAN_FRONTEND=noninteractive apt-get -qq update)
  PKG_INSTALL=(env DEBIAN_FRONTEND=noninteractive apt-get -y -qq install)
elif command -v dnf >/dev/null 2>&1; then
  PKG_UPDATE=(dnf -q -y makecache)
  PKG_INSTALL=(dnf -q -y install)
else
  echo "Unsupported package manager. Neo supports Debian/Ubuntu (apt) and Enterprise Linux/Fedora (dnf)." >&2
  exit 1
fi

for bin in curl tar; do
  command -v "$bin" >/dev/null 2>&1 || {
    "${PKG_UPDATE[@]}" >/dev/null 2>&1 || true
    "${PKG_INSTALL[@]}" curl tar >/dev/null 2>&1
  }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading ${REPO}@${REF} ..."
curl -fsSL "https://codeload.github.com/${REPO}/tar.gz/${REF}" -o "$tmp/src.tar.gz"
if [[ -n $SHA256 ]]; then
  got=$(sha256sum "$tmp/src.tar.gz" | cut -d' ' -f1)
  if [[ $got != "$SHA256" ]]; then
    echo "Checksum mismatch for ${REPO}@${REF}: expected $SHA256, got $got. Nothing was installed." >&2
    exit 1
  fi
  echo "Checksum OK."
elif [[ $REF == main ]]; then
  echo "Note: installing latest development version (main). Pin a release with NEO_REF." >&2
fi

mkdir -p "$tmp/src"
tar -xzf "$tmp/src.tar.gz" --strip-components=1 -C "$tmp/src"
[[ -f $tmp/src/neo.sh ]] || { echo "The downloaded archive does not look like Neo (no neo.sh)." >&2; exit 1; }

if [[ -n $DEST && $DEST != / && -f $DEST/neo.sh ]]; then
  find "$DEST" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi
mkdir -p "$DEST"
cp -a "$tmp/src/." "$DEST/"
chmod +x "$DEST/neo.sh"

rm -rf "$tmp"; trap - EXIT

ln -sfn "$DEST/neo.sh" /usr/local/bin/neo
echo "🐱 Neo installed in $DEST. From now on run: sudo neo [command]   (see: neo --help)"
[[ ${NEO_NO_RUN:-0} == 1 ]] && exit 0

if [[ ! -t 0 && -r /dev/tty ]]; then
  exec "$DEST/neo.sh" "$@" </dev/tty
fi
exec "$DEST/neo.sh" "$@"
