#!/usr/bin/env bash
#
# Install the pdocker command by symlinking it onto your PATH.
#
# This deliberately does not append to ~/.bash_profile or ~/.zshrc: repeated
# runs would stack up duplicate aliases, and a symlink works the same in every
# shell. Uninstall with: rm ~/.local/bin/pdocker

set -euo pipefail

# Piped into bash there is no BASH_SOURCE, and no repo to install from; that
# is what bootstrap.sh is for.
if [[ -z "${BASH_SOURCE[0]:-}" ]]; then
	echo "[-] install.sh must be run from a pdocker checkout." >&2
	echo "    To install from GitHub instead, use bootstrap.sh:" >&2
	echo "      curl -fsSL https://raw.githubusercontent.com/g31s/pdocker/master/bootstrap.sh | bash" >&2
	exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")"

SRC="$PWD/pdocker.sh"
BIN_DIR="${PDOCKER_BIN_DIR:-$HOME/.local/bin}"
DEST="$BIN_DIR/pdocker"

chmod +x "$SRC" build.sh

mkdir -p "$BIN_DIR"

if [[ -e "$DEST" && ! -L "$DEST" ]]; then
	echo "[-] $DEST exists and is not a symlink. Move it aside first." >&2
	exit 1
fi

ln -sfn "$SRC" "$DEST"
echo "[*] Linked $DEST -> $SRC"

case ":$PATH:" in
	*":$BIN_DIR:"*)
		echo "[*] Ready. Run: pdocker help"
		;;
	*)
		echo "[!] $BIN_DIR is not on your PATH. Add this to your shell rc file:"
		echo "      export PATH=\"$BIN_DIR:\$PATH\""
		;;
esac
