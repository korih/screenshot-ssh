# P2-WINWIRE: Windows glue, CLI Windows bits, WSL ssh_dir offer
Phase: 2  Tier: sonnet  Deps: P2-WINCLIP, P2-WINHOOK, P2-WINSVC, P1-CLI  Branch: cross-platform-go/P2-WINWIRE
Plan: PLAN.md §3 (Config, Windows specifics), §5 P2-WINWIRE

## Goal
Assemble the Windows pieces into `platform.Platform`, make `sshot daemon/install/uninstall/doctor` work on Windows, and help users whose SSH keys live in WSL.

## Context (pasted, not linked)
- Pieces: clipboard (P2-WINCLIP), hook/window/input/notify (P2-WINHOOK), autostart/instance/log (P2-WINSVC) in `internal/platform/windows`. `internal/platform/native/native_windows.go` is a placeholder from P1-DAEMON returning "not implemented"; replace it with `return windows.New()`.
- `daemon` on Windows: acquire the instance mutex, redirect logging to the log file when stdout is not a console (sshotw.exe), cancel ctx on the stop event, then `daemon.Run`.
- `cmd/sshot` (P1-CLI) exposes `var suggestSSHDir func(host string) (string, bool)`; add `cmd/sshot/sshdir_windows.go` setting it in `init`: list distros with `wsl.exe -l -q` (output is UTF-16LE with NULs: decode), for each check `\\wsl.localhost\<distro>\home\*\.ssh\config` or key files that mention/serve the host; `machine add` then asks `Use SSH keys and config from <path>? [y/N]` (only when stdin is a terminal) and saves `ssh_dir`.
- Doctor on Windows adds: `ssh_dir` source and whether `\\.\pipe\openssh-ssh-agent` is reachable (optional check).
- Two binaries: `go build ./cmd/sshot` → `sshot.exe`; `go build -ldflags=-H=windowsgui ./cmd/sshot` → `sshotw.exe`.
- Manual check is a user gate: stop `blocked: needs-user` with the exact steps from PLAN.md §5 P2-WINWIRE after the automated acceptance passes. The user runs `machine add` on their real host.

## Owns (may create or modify)
- `internal/platform/windows/platform_windows.go`
- `internal/platform/native/native_windows.go`
- `cmd/sshot/*_windows.go` (new files only; do not edit files P1-CLI created except through the `suggestSSHDir` seam)

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. `windows.New()` and `native_windows.go`; daemon startup on Windows with mutex, log, stop event.
2. `sshdir_windows.go` WSL suggestion with a unit test for the UTF-16 distro list parsing.
3. Build both exes, run acceptance, then hand the manual check to the user.

## Acceptance (run verbatim before marking done)
- `S=$(mktemp -d); GOOS=windows go build -o $S/sshot.exe ./cmd/sshot && GOOS=windows go build -ldflags=-H=windowsgui -o $S/sshotw.exe ./cmd/sshot` → exits 0
- `[ "$($S/sshot.exe version | tr -d '\r')" = "sshot $(scripts/payload-stamp.sh)" ] && echo SAME` → `SAME`
- `scripts/wintest.sh ./cmd/sshot` → `PASS`
- Handoff records the user's manual check result (all items in PLAN.md §5 P2-WINWIRE) as PASS.

## Out of scope
- Installer and release (P2-WINDIST).
