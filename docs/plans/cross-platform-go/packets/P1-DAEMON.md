# P1-DAEMON: Platform interface, fake platform, interceptor logic
Phase: 1  Tier: sonnet  Deps: P1-CONFIG, P1-IMAGE  Branch: cross-platform-go/P1-DAEMON
Plan: PLAN.md §3 (Seams, Ported behaviour), §5 P1-DAEMON

## Goal
Define the OS abstraction every native client implements and port the interceptor logic (decide, upload, paste, restore) into platform-neutral Go tested with a fake platform. Windows and macOS packets then only implement the interface.

## Context (pasted, not linked)
- Contract to create in `internal/platform/platform.go` is given verbatim in PLAN.md §3 "Seams" (Platform, Clipboard, Autostart, KeyEvent, Chord, App). You may reuse `config.Chord` for `Chord`. Keep it small; document that `Clipboard.HasImage` and `Frontmost`/`WindowTitle` are called from the hook and must be fast.
- `internal/platform/native/`: `func New() (platform.Platform, error)` in three files. `native_other.go` (`//go:build !windows && !(darwin && cgo)`) returns an error containing `unsupported` (`the paste daemon is not supported on <GOOS>`). `native_windows.go` and `native_darwin.go` (`//go:build darwin && cgo`) are placeholders returning `the paste daemon is not implemented on <GOOS> yet`; P2-WINWIRE and P3-MACSVC take them over.
- Interceptor (`mac/Sources/sshot/EventTap.swift:76-158`):
  - handle(event): pass if synthetic or autorepeat; pass unless chord ∈ config paste keys; pass unless frontmost app ID ∈ `terminal_apps` (case-insensitive on Windows: compare with `strings.EqualFold` always); pass unless `Clipboard.HasImage()`.
  - routing: host = default machine; if global `title_match` or any machine `title_match` is set, get the window title; first machine whose regex matches wins; else if global regex set and does not match → pass.
  - if busy → swallow (return true) without doing anything; else set busy, swallow, and asynchronously: `ReadImages`, upload each via an `Uploader` interface (`Upload(imaging.Source) (string, error)`, satisfied by `internal/remote`), join paths with a space, then paste.
  - paste(text, event): `Snapshot`, `SetText(text)`, remember `ChangeCount`, `PostPaste(event)`, after 500 ms restore the snapshot only if `ChangeCount` is unchanged, then clear busy.
  - fail(err): log `error: <err>`, `Beep()`, `Notify("Upload failed: <err>")`, clear busy.
- Startup (`EventTap.swift:58-71`): in the background, for each machine sorted by host: `Sync` (log `<host>: updated sshot <from|(none)> -> <stamp>` when installed), then resolve remote dir (log `<host>: remote dir <dir>`); on error log `warning: could not reach <host>: <err>`. Take a `Syncer` interface so tests use fakes.
- `Daemon.run` (`EventTap.swift:177-214`): log `sshot <stamp> daemon starting (machines a,b, default x, apps …)`, `WaitForPermission`, then `RunHook`. Regex compile error → `invalid title_match regex "<p>": <err>`.
- The timer and goroutines must be injectable (a clock or `afterFunc`) so tests do not sleep 500 ms each.
- `internal/platform/fake`: records calls (SetText, PostPaste, Restore, Beep, Notify), scriptable clipboard state and frontmost app, and a way to feed KeyEvents.

## Owns (may create or modify)
- `internal/platform/platform.go`
- `internal/platform/fake/**`
- `internal/platform/native/native_other.go`, `native_windows.go` (placeholder), `native_darwin.go` (placeholder)
- `internal/daemon/**`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. `platform.go`, `fake`, the three `native` files; `go build` for linux/windows/darwin(no cgo) passes.
2. Interceptor decision and routing with table tests.
3. Upload/paste/restore/busy/fail flow and startup sync with fakes.

## Acceptance (run verbatim before marking done)
- `go test ./internal/daemon/... ./internal/platform/... -count=1` → `ok`
- `go build ./... && GOOS=windows go build ./... && GOOS=darwin CGO_ENABLED=0 go build ./...` → exits 0

## Out of scope
- Any real OS API. CLI wiring of `sshot daemon` (P1-CLI).
