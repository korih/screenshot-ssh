# P3-DOCS: Cross-platform README
Phase: 3  Tier: haiku  Deps: P3-UNIFY  Branch: cross-platform-go/P3-DOCS
Plan: PLAN.md §5 P3-DOCS

## Goal
Rewrite README.md for the unified Go client on macOS and Windows.

## Context (pasted, not linked)
- Current README sections: intro (Mac-only wording, Cmd+Ctrl+Shift+4 / Cmd+V), Install (curl | sh, build from source with Xcode CLT), machine add, Versions stay in sync, Several machines, Usage table, Config (Mac), Updating and development, Releasing, Troubleshooting, License. P2-WINDIST added a Windows section.
- Changes: intro covers both OSes (Windows: Win+Shift+S, Ctrl+V or Ctrl+Shift+V); Install split into macOS (`curl … install.sh | sh`) and Windows (`irm … install.ps1 | iex`); building from source needs Go (no Xcode/Swift); Config section titled "Config" with `ssh_dir`, `paste_keys`, Windows `terminal_apps` defaults (exe names) and macOS defaults (bundle IDs), config path on each OS; Troubleshooting: Windows log `%LOCALAPPDATA%\sshot\sshot.log`, macOS log `~/Library/Logs/sshot.log`, strict known_hosts and `--accept-new-host-key`, keys in WSL via `ssh_dir`, Accessibility re-grant after the switch from the Swift build; Releasing: assets are `sshot-macos.tar.gz` and `sshot-windows-{amd64,arm64}.zip`. Remove "uses ControlMaster" wording (now one in-process connection per machine).
- Keep the badge, MIT license section, and all GitHub URLs.

## Owns (may create or modify)
- `README.md`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. Rewrite README.md.

## Acceptance (run verbatim before marking done)
- `grep -c -i 'windows' README.md` → ≥ 3
- `grep -niE 'swift build|xcode' README.md` → no output
- `grep -c 'install.ps1' README.md` → ≥ 1

## Out of scope
- Code changes.
