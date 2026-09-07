#!/usr/bin/env bash
#
# Build the pdocker base image. Installing the `pdocker` command is a separate
# step: see ./install.sh.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

IMAGE="${PDOCKER_IMAGE:-pdocker:latest}"

command -v docker >/dev/null 2>&1 || { echo "[-] docker not found in PATH." >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "[-] Cannot reach the Docker daemon. Is Docker running?" >&2; exit 1; }

echo "[*] Building $IMAGE ..."

# UID/GID are baked in so files written to the mounted volume are owned by you.
# No sudo: Docker Desktop does not need it, and running as root would build
# into root's Docker context instead of yours.
docker build \
	--rm \
	--build-arg "UID=$(id -u)" \
	--build-arg "GID=$(id -g)" \
	-t "$IMAGE" \
	"$@" \
	.

echo "[*] Built $IMAGE."
echo "[*] Next: ./install.sh, then run 'pdocker new'."
