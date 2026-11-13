# P1-CLI: cmd/sshot, all commands and doctor
Phase: 1  Tier: sonnet  Deps: P1-REMOTE, P1-DAEMON  Branch: cross-platform-go/P1-CLI
Plan: PLAN.md §2, §5 P1-CLI

## Goal
The `sshot` command in Go with the same commands, output and errors as the Swift client, running on any OS; the daemon and autostart go through `native.New()`.

## Context (pasted, not linked)
- Usage text and commands: `mac/Sources/sshot/main.swift:3-20`. Keep it verbatim except: `install` says "background daemon (autostart)" instead of LaunchAgent; `machine add` gains `[--accept-new-host-key]`.
- Option helpers `takeOption`/`takeFlag` (`main.swift:27-42`): flags may appear anywhere; `<name> needs a value`; errors print `sshot: <msg>` to stderr and exit 1.
- `applyConfig` (`main.swift:45-61`): no machines → uninstall autostart if installed and print `no machines left; stopped the daemon`; otherwise (re)install autostart and on first time print the start message (macOS adds the Accessibility hint; take the hint text from the platform or a GOOS switch).
- `machine add/remove/list/sync/default`: `main.swift:63-175`. `add` first runs `true` over SSH and on failure prints the "cannot ssh to <host> without a prompt" message (`main.swift:77-83`); with the strict known_hosts error from sshx, include its hint. Then install the payload and print its output, update config, set default if needed, `added <host>[ (default)]`.
- `list`: `this Mac: <stamp>` becomes `this computer: <stamp>`; per machine `*`/space, host, remote dir, `up to date` / `out of date (<x>)` / `not installed` / `unreachable`, optional `title_match=`.
- `send [-m host] [file ...]` (`main.swift:182-196`): no files → clipboard via `native.New()` (on unsupported OS print the unsupported error); files must exist (`no such file: <p>`) and pass `imaging.IsImageFile`? Swift accepts any file path and `prepared` decodes it; keep: decode errors surface.
- `doctor` (`LaunchAgent.swift:66-95`): config check, per machine `ssh + remote dir` and `remote version`, then `autostart` state from the platform (Linux: `!` optional, not a failure), last log line from `platform.LogPath()`. Also print `ssh_dir: <path>`.
- `upgrade [--force]` (`mac/Sources/sshot/Upgrade.swift`): Unix runs `/bin/sh -c "set -o pipefail 2>/dev/null; curl -fsSL <install.sh url> | sh"` with `SSHOT_BIN_DIR` = dir of the resolved executable and `SSHOT_FORCE=1` if forced. Windows (`upgrade_windows.go`) runs `powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/korih/screenshot-ssh/master/install.ps1 | iex"` with `SSHOT_INSTALL_DIR` and `SSHOT_FORCE`. (install.ps1 lands in P2-WINDIST.)
- `version`: `sshot <stamp>`. `daemon`: `daemon.Run` with `native.New()`.
- Provide a seam for P2-WINWIRE: `var suggestSSHDir = func(host string) (string, bool) { return "", false }` used by `machine add` when the connection fails because the host is not in `<ssh_dir>/config`/keys; P2-WINWIRE adds `sshdir_windows.go` that sets it in `init`.
- Tests use `SSHOT_CONFIG` and `internal/sshx/sshtest`; run the command functions in-process (factor `main` into `run(args []string, stdout, stderr io.Writer) int`).

## Owns (may create or modify)
- `cmd/sshot/**`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. `run()`, usage, option helpers, `version`, `help`, `send` (files), `daemon`/`install`/`uninstall` via platform.
2. `machine` subcommands with sshtest integration tests.
3. `doctor`, `upgrade` (unix + windows files), clipboard `send`.

## Acceptance (run verbatim before marking done)
- `S=$(mktemp -d); go build -o $S/sshot ./cmd/sshot && $S/sshot help | grep -c 'machine add'` → `1`
- `[ "$($S/sshot version)" = "sshot $(scripts/payload-stamp.sh)" ] && echo SAME` → `SAME`
- `go test ./cmd/sshot/... -count=1` → `ok`
- `GOOS=windows go build ./... && GOOS=darwin CGO_ENABLED=0 go build ./...` → exits 0

## Out of scope
- Native platform code. Installers.
