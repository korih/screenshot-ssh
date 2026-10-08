#!/usr/bin/env bash
# Build sshot from this checkout and install it. If the running daemon uses that binary,
# restart it and bring every machine to the new version.
set -euo pipefail

cd "$(dirname "$0")/.."
dest="${SSHOT_BIN_DIR:-$HOME/.local/bin}"
plist="$HOME/Library/LaunchAgents/com.sshot.daemon.plist"

swift build -c release
mkdir -p "$dest"
install -m 755 "$(swift build -c release --show-bin-path)/sshot" "$dest/sshot"
echo "installed $dest/sshot ($("$dest/sshot" version))"

daemon_bin="$(plutil -extract ProgramArguments.0 raw "$plist" 2>/dev/null || true)"
if [[ -n "$daemon_bin" && "$daemon_bin" -ef "$dest/sshot" ]]; then
  "$dest/sshot" install >/dev/null
  "$dest/sshot" machine sync || true
  echo "If Cmd+V stops working, re-allow sshot in System Settings > Privacy & Security > Accessibility."
else
  echo "Next: sshot machine add <ssh-host>   (e.g. user@10.0.0.5 or an alias from ~/.ssh/config)"
fi
