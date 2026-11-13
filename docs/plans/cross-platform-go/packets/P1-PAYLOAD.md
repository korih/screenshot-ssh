# P1-PAYLOAD: Embedded vm/ payload and Swift-identical stamp
Phase: 1  Tier: sonnet  Deps: —  Branch: cross-platform-go/P1-PAYLOAD
Plan: PLAN.md §3 (Layout, Ported behaviour), §5 P1-PAYLOAD

## Goal
Embed `VERSION` and every file under `vm/` into the Go binary and reproduce the Swift client's version stamp and install/uninstall scripts exactly, so Go and Swift clients agree on what is installed on each remote machine.

## Context (pasted, not linked)
- Swift stamp (`mac/Sources/sshot/Payload.swift:14-24`): SHA-256 hasher; for each file in `files` (sorted by relative path, `mac/Sources/sshot-embed/main.swift:28`) update with `path` UTF-8 bytes then the file's base64 string UTF-8 bytes (standard, padded: `Data.base64EncodedString()`); stamp = `"\(version)+\(hex.prefix(10))"`. `version` = `VERSION` contents trimmed of whitespace/newlines (`sshot-embed/main.swift:14`). Today `VERSION` = `0.2.0`.
- Relative paths look like `claude-commands/shot.md`, `install.sh`, `sshot`, `sshot-clean.service`, `sshot-clean.timer`, `uninstall.sh` (files under `vm/`, no `vm/` prefix).
- Mode: `perms & 0o111 != 0 ? 0o755 : 0o644` (`sshot-embed/main.swift:24`). Mode is NOT part of the hash. `go:embed` drops modes, so keep an explicit executable set: `install.sh`, `sshot`, `uninstall.sh` (currently 100755 in `git ls-files -s vm`).
- Install script (`Payload.swift:27-41`): lines `set -euo pipefail`, `tmp=$(mktemp -d)`, `trap 'rm -rf "$tmp"' EXIT`; per file: `mkdir -p "$tmp"/<quoted dir>` if the path has a dir, `printf %s <quoted base64> | base64 -d > "$tmp"/<quoted path>`, `chmod <octal mode> "$tmp"/<quoted path>`; finally `SSHOT_VERSION=<quoted stamp> bash "$tmp/install.sh"`. Joined with `\n`, trailing newline. Quote = POSIX single-quote (`Shell.swift:63-65`: `'` + s.replace("'", "'\\''") + `'`).
- Uninstall script (`Payload.swift:43-47`) and `versionPath = "~/.local/share/sshot/version"`: copy verbatim.
- `go:embed` cannot reach parent directories, so the embed lives at the repo root: `assets.go`, `package sshotassets`, `//go:embed VERSION vm` exposing an `embed.FS`. `go.mod` already exists (orchestrator prep), module `github.com/korih/screenshot-ssh`.
- `vm/install.sh` with `SSHOT_VERSION` set installs `~/.local/bin/sshot` whose `version` command prints that value; with no systemd user session it skips the timer (`vm/install.sh:17-26`). CI runs it with `unset XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS` and a temp HOME (`.github/workflows/ci.yml`, job `shell`).

## Owns (may create or modify)
- `assets.go`
- `internal/payload/**`
- `scripts/payload-stamp.sh`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- `go.mod`/`go.sum` with the pre-approved modules; `.gitattributes` forcing LF in `vm/**` and `VERSION`.

## Steps (each ends in tests + commit + handoff checkpoint)
1. `assets.go` + `internal/payload`: `Files()` (sorted, with base64 and mode), `Version()`, `Stamp()`. Test `TestExecModesMatchGit` compares the executable set to `git ls-files -s vm` (skip if git is unavailable).
2. `scripts/payload-stamp.sh`: an independent bash implementation (find, sort, `base64 -w0`, `sha256sum`) printing the stamp. Test `TestStampMatchesShell` runs it and compares.
3. `InstallScript()`, `UninstallScript()`, `VersionPath`, `Quote()`. Test `TestInstallScriptInstalls` pipes the script to `bash -s` with a temp HOME and `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS` unset, then checks `$HOME/.local/bin/sshot version` == `Stamp()` and `$HOME/.local/share/sshot/version` content.

## Acceptance (run verbatim before marking done)
- `go test ./internal/payload/... -count=1` → `ok`
- `go test ./internal/payload -run 'TestStampMatchesShell|TestExecModesMatchGit|TestInstallScriptInstalls' -v -count=1 | grep -c '^--- PASS'` → `3`
- `scripts/payload-stamp.sh | grep -Eq '^0\.2\.0\+[0-9a-f]{10}$' && echo OK` → `OK`
- `shellcheck scripts/payload-stamp.sh` → exits 0

## Out of scope
- Any change to `vm/` or the Swift sources. Remote execution (P1-REMOTE).
