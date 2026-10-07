#!/usr/bin/env bash
# Install the VM side of sshot: CLI, cleanup timer, and Claude Code /shot command.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.cache/sshot" "$HOME/.local/bin" "$HOME/.claude/commands"
install -m 755 "$here/sshot" "$HOME/.local/bin/sshot"
install -m 644 "$here/claude-commands/shot.md" "$HOME/.claude/commands/shot.md"

if command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/systemd/user"
  install -m 644 "$here/sshot-clean.service" "$here/sshot-clean.timer" "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload
  systemctl --user enable --now sshot-clean.timer
  echo "Enabled sshot-clean.timer (deletes screenshots older than 7 days)."
else
  echo "systemd user session not available; skipping cleanup timer. Run 'sshot clean' manually or via cron."
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Note: add ~/.local/bin to your PATH." ;;
esac

echo "VM side installed. Screenshots will land in ~/.cache/sshot; use /shot in Claude Code."
