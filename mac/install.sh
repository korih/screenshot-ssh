#!/usr/bin/env bash
# Build sshot, install it, write a config if needed, and start the background daemon.
set -euo pipefail

cd "$(dirname "$0")"
dest="${PREFIX:-$HOME/.local/bin}"

swift build -c release
bin="$(swift build -c release --show-bin-path)/sshot"
mkdir -p "$dest"
install -m 755 "$bin" "$dest/sshot"
echo "installed $dest/sshot"

if [[ ! -f "$HOME/.config/sshot/config.json" ]]; then
  read -rp "SSH host (alias from ~/.ssh/config) for your VM: " host
  "$dest/sshot" init "$host"
fi

"$dest/sshot" install
sleep 2
"$dest/sshot" doctor || true

case ":$PATH:" in
  *":$dest:"*) ;;
  *) echo "Note: add $dest to your PATH to use 'sshot' directly." ;;
esac
