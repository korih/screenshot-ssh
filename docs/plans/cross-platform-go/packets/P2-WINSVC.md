# P2-WINSVC: Autostart, single instance, log file
Phase: 2  Tier: sonnet  Deps: P1-DAEMON, P1-CI  Branch: cross-platform-go/P2-WINSVC
Plan: PLAN.md §3 (Windows specifics), §5 P2-WINSVC

## Goal
Windows equivalents of the LaunchAgent and log: start the daemon at login without a console window, keep one instance, and log to a file `doctor` can read.

## Context (pasted, not linked)
- Interface `platform.Autostart{Install(exe string) error; Uninstall() error; State() (string, bool)}` and `LogPath() string` (P1-DAEMON).
- Swift `LaunchAgent.install` (`mac/Sources/sshot/LaunchAgent.swift:12-37`) writes the agent and (re)starts the daemon; `uninstall` stops and removes it; `state` returns a status string or nil.
- Windows: value `sshot` under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` = `"<dir>\sshotw.exe" daemon` (sshotw.exe is the `-H=windowsgui` build next to `sshot.exe`; `Install(exe)` derives it from the given `sshot.exe` path and falls back to `exe` itself if `sshotw.exe` is missing). `Install` also stops a running daemon and starts a new one detached (`CREATE_NO_WINDOW | DETACHED_PROCESS`). Make the value name a package variable so tests use `sshot-test-<pid>`.
- Single instance: named mutex `Local\sshot-daemon`; `AcquireInstance() (release func(), err error)`; second acquisition → error `sshot daemon is already running`. `Uninstall` and `Install` stop the running daemon: a named event `Local\sshot-daemon-stop` the daemon waits on (expose `StopSignal() <-chan struct{}` for P2-WINWIRE to wire into ctx) plus wait up to 3 s for the mutex to free.
- `State()`: `running (pid N)` / `installed, not running` / not installed → `("", false)`. Store the pid in `%LOCALAPPDATA%\sshot\daemon.pid`.
- Log: `%LOCALAPPDATA%\sshot\sshot.log`; `OpenLog() (io.WriteCloser, error)` appending; truncate to the last 1 MB at open if larger.
- Use `golang.org/x/sys/windows/registry` and `windows.CreateMutex`/`CreateEvent`.

## Owns (may create or modify)
- `internal/platform/windows/{autostart,instance,logfile}*_windows.go` and tests

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. Run-key autostart with a test value name; tests write, read state, delete.
2. Mutex, stop event, pid file, log file; tests.

## Acceptance (run verbatim before marking done)
- `scripts/wintest.sh ./internal/platform/windows -run 'Autostart|Instance|LogFile'` → `PASS`
- `reg.exe query 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' | grep -c sshot-test` → `0` (tests cleaned up)

## Out of scope
- Writing the real `sshot` value on the user's machine (user gate; happens only when the user runs `sshot install`).
