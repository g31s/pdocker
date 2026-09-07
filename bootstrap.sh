#!/usr/bin/env bash
#
# One-line installer for pdocker:
#
#   curl -fsSL https://raw.githubusercontent.com/g31s/pdocker/master/bootstrap.sh | bash
#
# pdocker is not a single script - it needs its Dockerfile, dotfiles and
# templates - so this clones the repo to a stable location and symlinks the
# command onto your PATH. Re-running it updates an existing install, which
# makes the same one-liner both the installer and the repair tool.
#
# Deliberately self-contained: piped into bash there is no $BASH_SOURCE and no
# repo on disk yet, so nothing here may reference either.

set -euo pipefail

REPO="${PDOCKER_REPO:-https://github.com/g31s/pdocker.git}"
REF="${PDOCKER_REF:-master}"
SRC_DIR="${PDOCKER_SRC:-${HOME}/.local/share/pdocker}"
BIN_DIR="${PDOCKER_BIN_DIR:-${HOME}/.local/bin}"
IMAGE="${PDOCKER_IMAGE:-pdocker:latest}"
FORCE_BUILD=0
NO_BUILD=0

while [[ "$#" -gt 0 ]]; do
	case "$1" in
		--build)    FORCE_BUILD=1; shift ;;
		--no-build) NO_BUILD=1; shift ;;
		--ref)      REF="${2:-master}"; shift 2 ;;
		-h|--help)
			echo "Usage: bootstrap.sh [--build|--no-build] [--ref <branch|tag>]"
			echo
			echo "The base image is built automatically when it is missing."
			echo "  --build     rebuild it even if it already exists"
			echo "  --no-build  never build it"
			exit 0 ;;
		*) echo "[-] Unknown option: $1" >&2; exit 1 ;;
	esac
done

info() { printf '[*] %s\n' "$*"; }
die()  { printf '[-] %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required."

if [[ -d "$SRC_DIR/.git" ]]; then
	info "Updating existing install at $SRC_DIR ..."
	git -C "$SRC_DIR" diff --quiet 2>/dev/null \
		|| die "Local changes in $SRC_DIR. Commit or stash them, then re-run."
	BEFORE="$(git -C "$SRC_DIR" rev-parse HEAD)"
	git -C "$SRC_DIR" fetch --quiet origin
	# --ff-only: never rewrite or merge over what is already there.
	git -C "$SRC_DIR" checkout --quiet "$REF" 2>/dev/null || true
	git -C "$SRC_DIR" pull --quiet --ff-only origin "$REF" \
		|| die "Could not fast-forward $SRC_DIR to $REF."
else
	[[ -e "$SRC_DIR" ]] && die "$SRC_DIR exists but is not a git checkout."
	info "Cloning $REPO -> $SRC_DIR ..."
	mkdir -p "$(dirname "$SRC_DIR")"
	git clone --quiet "$REPO" "$SRC_DIR"
	git -C "$SRC_DIR" checkout --quiet "$REF" 2>/dev/null \
		|| die "No such branch or tag: $REF"
fi

# If the pull changed anything the image is built from, the existing image is
# stale and "already built" would be the wrong answer.
if [[ -n "${BEFORE:-}" ]]; then
	AFTER="$(git -C "$SRC_DIR" rev-parse HEAD)"
	if [[ "$BEFORE" != "$AFTER" ]] && git -C "$SRC_DIR" diff --name-only "$BEFORE" "$AFTER" \
		| grep -qE '^(Dockerfile|dotfiles/|build\.sh)'; then
		info "The base image inputs changed in this update; rebuilding."
		FORCE_BUILD=1
	fi
fi

chmod +x "$SRC_DIR/pdocker.sh" "$SRC_DIR/build.sh" "$SRC_DIR/install.sh" 2>/dev/null || true

mkdir -p "$BIN_DIR"
if [[ -e "$BIN_DIR/pdocker" && ! -L "$BIN_DIR/pdocker" ]]; then
	die "$BIN_DIR/pdocker exists and is not a symlink. Move it aside first."
fi
ln -sfn "$SRC_DIR/pdocker.sh" "$BIN_DIR/pdocker"
info "Linked $BIN_DIR/pdocker -> $SRC_DIR/pdocker.sh"
# Read the version out of the file rather than executing it: --ref may point
# at an old release whose script has different commands (or side effects).
VERSION="$(grep -m1 '^readonly PDOCKER_VERSION=' "$SRC_DIR/pdocker.sh" 2>/dev/null \
	| sed 's/.*"\(.*\)".*/\1/' || true)"
info "Installed pdocker ${VERSION:-(version unknown)}"

case ":$PATH:" in
	*":$BIN_DIR:"*) ;;
	*)
		printf '[!] %s is not on your PATH. Add this to your shell rc file:\n' "$BIN_DIR"
		# shellcheck disable=SC2016  # $PATH stays literal: it is a line to copy.
		printf '      export PATH="%s:$PATH"\n' "$BIN_DIR"
		;;
esac

# Build the base image as part of installing, because pdocker cannot do
# anything without it. But skip it when the image is already there (this script
# is also the update path), and never fail the install just because Docker is
# unreachable - the install itself succeeded.
build_hint() {
	info "Build it later with:  $SRC_DIR/build.sh"
}

if [[ "$NO_BUILD" -eq 1 ]]; then
	info "Skipping the image build (--no-build)."
	build_hint
elif ! command -v docker >/dev/null 2>&1; then
	printf '[!] docker is not installed, so the base image was not built.\n' >&2
	build_hint
elif ! docker info >/dev/null 2>&1; then
	printf '[!] Cannot reach the Docker daemon, so the base image was not built.\n' >&2
	printf '[!] On Linux this is usually socket permissions:\n' >&2
	# shellcheck disable=SC2016  # literal: this is a line for the user to copy.
	printf '[!]       sudo usermod -aG docker "$USER" && newgrp docker\n' >&2
	build_hint
elif [[ "$FORCE_BUILD" -eq 0 ]] && docker image inspect "$IMAGE" >/dev/null 2>&1; then
	info "Base image $IMAGE is already built (use --build to rebuild it)."
else
	info "Building the base image ..."
	"$SRC_DIR/build.sh"
fi

info "Ready. Try:  pdocker new myproject"
