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
DO_BUILD=0

while [[ "$#" -gt 0 ]]; do
	case "$1" in
		--build) DO_BUILD=1; shift ;;
		--ref)   REF="${2:-master}"; shift 2 ;;
		-h|--help)
			echo "Usage: bootstrap.sh [--build] [--ref <branch|tag>]"
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

if [[ "$DO_BUILD" -eq 1 ]]; then
	"$SRC_DIR/build.sh"
else
	info "Next: build the base image with"
	info "  $SRC_DIR/build.sh"
	info "Then: pdocker new myproject      (later: pdocker update)"
fi
