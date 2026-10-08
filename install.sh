#!/bin/sh
# Install or update sshot on macOS by building it from source.
#   curl -fsSL https://forgejo.korih.com/k/screenshot-transfer/raw/branch/master/install.sh | sh
# Env: SSHOT_REF (branch or tag, default master), SSHOT_SRC (checkout dir),
#      SSHOT_BIN_DIR (default ~/.local/bin), SSHOT_FORCE=1 (rebuild even if up to date).
set -eu

repo="${SSHOT_REPO:-https://forgejo.korih.com/k/screenshot-transfer.git}"
ref="${SSHOT_REF:-master}"
src="${SSHOT_SRC:-$HOME/.local/share/sshot/src}"
dest="${SSHOT_BIN_DIR:-$HOME/.local/bin}"

[ "$(uname -s)" = Darwin ] || { echo "sshot: this installer is for macOS; remote machines are set up with 'sshot machine add'" >&2; exit 1; }
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  echo "sshot: needs the Xcode Command Line Tools. Run 'xcode-select --install', then run this again." >&2
  exit 1
fi

if [ -d "$src/.git" ]; then
  before="$(git -C "$src" rev-parse HEAD)"
  git -C "$src" fetch -q --depth 1 origin "$ref"
  git -C "$src" checkout -q --force FETCH_HEAD
else
  before=""
  mkdir -p "$(dirname "$src")"
  rm -rf "$src"
  git clone -q --depth 1 --branch "$ref" "$repo" "$src"
fi
after="$(git -C "$src" rev-parse HEAD)"

if [ "$before" = "$after" ] && [ -x "$dest/sshot" ] && [ -z "${SSHOT_FORCE:-}" ]; then
  echo "sshot is up to date ($("$dest/sshot" version), ${after%"${after#???????}"})"
  exit 0
fi

echo "building sshot from $repo ($ref, ${after%"${after#???????}"})"
SSHOT_BIN_DIR="$dest" "$src/scripts/install-from-source.sh"

case ":$PATH:" in
  *":$dest:"*) ;;
  *) echo "Note: add $dest to your PATH." ;;
esac
