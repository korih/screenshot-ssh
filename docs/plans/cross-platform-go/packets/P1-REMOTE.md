# P1-REMOTE: Remote install/sync/uninstall and uploader
Phase: 1  Tier: sonnet  Deps: P1-PAYLOAD, P1-SSH  Branch: cross-platform-go/P1-REMOTE
Plan: PLAN.md §3 (Ported behaviour), §5 P1-REMOTE

## Goal
Port the Swift `Remote` and `Uploader` logic onto the in-process SSH pool so the CLI and daemon can install sshot on machines, keep them in sync, and upload images.

## Context (pasted, not linked)
- `Remote` (`mac/Sources/sshot/Payload.swift:51-78`): `installedStamp(host)` runs `cat ~/.local/share/sshot/version 2>/dev/null || true`, trims, empty → not installed; `install` runs `bash -s` with `payload.InstallScript()` on stdin and returns stdout; `uninstall` likewise with `payload.UninstallScript()`; `sync(host, force)` returns `current` if installed == stamp and not force, else installs and returns `installed(from: previous)`.
- `Uploader.remoteDir` (`mac/Sources/sshot/Uploader.swift:34-55`): cached per uploader under a mutex; `~` → `"$HOME"`, `~/x` → `"$HOME"/'x'`, else quoted path; runs `mkdir -p <expr> && cd <expr> && pwd -P`; last line must start with `/` else error `could not resolve remote dir <dir> on <host> (got <out>)`.
- `upload` (`Uploader.swift:58-75`): prepare image (`imaging.Prepare(src, maxDimension)`), remote path `<dir>/<fileName(ext)>`, put the bytes; on put failure clear the cached dir and return the error.
- `fileName(ext)` (`Uploader.swift:77-83`): local time `yyyy-MM-dd_HHmmss` + `-` + 4 lowercase hex chars + `.` + ext.
- Available: `internal/payload` (`Stamp()`, `InstallScript()`, `UninstallScript()`, `VersionPath`, `Quote()`), `internal/sshx` (`Pool.Get(host)`, `Client.Run(cmd, stdin)`, `Client.Put(path, data)`), `internal/sshx/sshtest` (exec via bash with HOME override + SFTP), `internal/imaging` (`Source`, `Prepare`). P1-IMAGE has no deps and is expected to be merged first; if `internal/imaging` is missing on your base, stop `blocked: P1-IMAGE not merged` rather than stubbing it.
- Machine type comes from `internal/config` (`Machine{Host, RemoteDir, TitleMatch}`) if merged; otherwise take `host, remoteDir string` parameters.

## Owns (may create or modify)
- `internal/remote/**`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. `InstalledStamp`, `Install`, `Uninstall`, `Sync` with sshtest integration tests (temp HOME, systemd vars unset).
2. `Uploader` with `RemoteDir`, `Upload`, `FileName`; tests for dir resolution (`~`, `~/x`, absolute), upload contents, name pattern, cache cleared after a failed put.

## Acceptance (run verbatim before marking done)
- `go test ./internal/remote/... -count=1` → `ok`

## Out of scope
- CLI output formatting (P1-CLI). Daemon startup sync loop (P1-DAEMON calls these).
