# P3-MACSVC: LaunchAgent, darwin glue, macOS CI
Phase: 3  Tier: sonnet  Deps: P3-MACCLIP, P3-MACHOOK, P1-CLI, P2-WINDIST  Branch: cross-platform-go/P3-MACSVC
Plan: PLAN.md §3 (macOS specifics), §5 P3-MACSVC

## Goal
Finish the Go macOS client: LaunchAgent autostart identical to Swift's, the `platform.Platform` glue, CI building it for both architectures, and the user's manual check that it replaces the Swift build.

## Context (pasted, not linked)
- Swift `LaunchAgent` (`mac/Sources/sshot/LaunchAgent.swift:3-62`): label `com.sshot.daemon`; plist `~/Library/LaunchAgents/com.sshot.daemon.plist` with `Label`, `ProgramArguments [exe, "daemon"]` (exe = resolved symlinks), `RunAtLoad true`, `KeepAlive true`, `ProcessType Interactive`, `StandardOutPath`/`StandardErrorPath` = `~/Library/Logs/sshot.log`; install = write XML plist, `launchctl bootout gui/<uid>/com.sshot.daemon` (if it succeeded sleep 1 s), `launchctl bootstrap gui/<uid> <plist>`; uninstall = bootout + delete; state = the `state = …` line of `launchctl print gui/<uid>/com.sshot.daemon`, else `loaded`, nil if print fails. `install.sh:20-30` reads `ProgramArguments.0` with `plutil`; keep it.
- `internal/platform/native/native_darwin.go` (`darwin && cgo`) is a placeholder from P1-DAEMON; replace with `return darwin.New()`.
- The CLI's `daemon` command must call `RunHook` on the main goroutine (P3-MACHOOK requirement). If P1-CLI runs the daemon elsewhere, fix it through a darwin-only file in `internal/platform/darwin` (e.g. `darwin.RunMain(func())`) and report any needed `cmd/sshot` change to the orchestrator rather than editing P1-CLI's files.
- CI (`.github/workflows/ci.yml`): the `go` macOS job must build with `CGO_ENABLED=1` for `GOARCH=arm64` and `amd64` (`CC="clang -arch x86_64"` for cross-arch) and run `go test ./... -count=1`; keep `stamp-parity`.
- Manual check (user gate): steps in PLAN.md §5 P3-MACSVC. Give the user exact commands: build on the Mac with `go build -o ~/.local/bin/sshot ./cmd/sshot`, `sshot install`, re-grant Accessibility, test, `sshot doctor`, `sshot machine list`.

## Owns (may create or modify)
- `internal/platform/darwin/{launchagent,platform}_darwin.go` (+ tests)
- `internal/platform/native/native_darwin.go`
- `.github/workflows/ci.yml`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. LaunchAgent: generate the plist XML with a template (no plist library: not pre-approved) and unit-test the bytes; `launchctl` calls behind a small runner interface for tests.
2. `darwin.New()`, `native_darwin.go`, CI changes. Stop `blocked: needs-user` for the push; check CI.
3. Stop `blocked: needs-user` for the manual Mac check; record the result.

## Acceptance (run verbatim before marking done)
- `GOOS=darwin CGO_ENABLED=0 go build ./...` → exits 0
- `gh run list -R korih/screenshot-ssh --branch cross-platform-go/P3-MACSVC --workflow ci --limit 1 --json conclusion -q '.[0].conclusion'` → `success`
- Handoff records the user's manual Mac check as PASS on every item.

## Out of scope
- Deleting Swift (P3-UNIFY).
