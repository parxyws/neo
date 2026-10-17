#!/usr/bin/env bash
# Spins up or enters a full systemd-enabled Ubuntu 24.04 container on Podman.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CONTAINER_NAME="neo-test"
IMAGE_NAME="neo-ubuntu:latest"

if [[ "${1:-}" =~ ^(--reset|-r|reset)$ ]]; then
  echo "==> Resetting container $CONTAINER_NAME..."
  podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
fi

if ! podman container exists "$CONTAINER_NAME" 2>/dev/null; then
  if ! podman image exists "$IMAGE_NAME" 2>/dev/null; then
    echo "==> Building $IMAGE_NAME ..."
    podman build -t "$IMAGE_NAME" -f tests/Containerfile.ubuntu .
  fi
  echo "==> Starting $CONTAINER_NAME with systemd on Podman..."
  podman run -d \
    --name "$CONTAINER_NAME" \
    --systemd=always \
    --privileged \
    -v "$PWD:/neo" \
    -p 8080:80 \
    -p 8443:443 \
    -p 3000:3000 \
    -p 2222:22 \
    "$IMAGE_NAME"
fi

if [[ $(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null) != "true" ]]; then
  echo "==> Starting existing container $CONTAINER_NAME..."
  podman start "$CONTAINER_NAME"
fi

echo "==> Entering $CONTAINER_NAME (run './neo.sh' inside /neo) ..."
podman exec -it "$CONTAINER_NAME" bash -c "cd /neo && exec bash"
