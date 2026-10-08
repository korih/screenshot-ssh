#!/usr/bin/env bash
# Remove the VM side of sshot. Screenshots in ~/.cache/sshot are deleted too.
set -euo pipefail

if command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user disable --now sshot-clean.timer >/dev/null 2>&1 || true
  rm -f "$HOME/.config/systemd/user/sshot-clean.service" "$HOME/.config/systemd/user/sshot-clean.timer"
  systemctl --user daemon-reload || true
fi
rm -f "$HOME/.local/bin/sshot" "$HOME/.claude/commands/shot.md"
rm -rf "$HOME/.local/share/sshot" "$HOME/.cache/sshot"
echo "sshot removed."
