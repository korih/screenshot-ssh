#!/usr/bin/env bash
# Install the VM side of sshot: CLI, cleanup timer, and Claude Code /shot command.
# Normally run by `sshot machine add` on the Mac, which sets SSHOT_VERSION.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
version="${SSHOT_VERSION:-dev}"
share="$HOME/.local/share/sshot"

mkdir -p "$HOME/.cache/sshot" "$HOME/.local/bin" "$HOME/.claude/commands" "$share"
sed "s|@VERSION@|$version|" "$here/sshot" > "$HOME/.local/bin/sshot.tmp"
chmod 755 "$HOME/.local/bin/sshot.tmp"
mv -f "$HOME/.local/bin/sshot.tmp" "$HOME/.local/bin/sshot"
install -m 644 "$here/claude-commands/shot.md" "$HOME/.claude/commands/shot.md"
install -m 755 "$here/uninstall.sh" "$share/uninstall.sh"

if command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/systemd/user"
  install -m 644 "$here/sshot-clean.service" "$here/sshot-clean.timer" "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload
  systemctl --user enable --now sshot-clean.timer >/dev/null 2>&1
  echo "Enabled sshot-clean.timer (deletes screenshots older than 7 days)."
else
  echo "systemd user session not available; skipping cleanup timer. Run 'sshot clean' manually or via cron."
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Note: add ~/.local/bin to your PATH." ;;
esac

# Written last: the Mac compares this to its own version to decide whether to reinstall.
printf '%s\n' "$version" > "$share/version"
echo "sshot $version installed. Screenshots will land in ~/.cache/sshot; use /shot in Claude Code."
