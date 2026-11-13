# P1-CONFIG: Config load/save, legacy format, per-OS defaults
Phase: 1  Tier: sonnet  Deps: —  Branch: cross-platform-go/P1-CONFIG
Plan: PLAN.md §3 (Config), §5 P1-CONFIG

## Goal
A Go `internal/config` package that reads and writes the same `config.json` the Swift client uses, plus the new `ssh_dir` and `paste_keys` keys and Windows defaults, so existing Mac users keep their config and Windows users get sensible defaults.

## Context (pasted, not linked)
- Swift model (`mac/Sources/sshot/Config.swift`): `Machine{host, remote_dir (default "~/.cache/sshot"), title_match?}`; `Config{machines, default?, terminal_apps (default list), title_match?, max_dimension (default 2000)}`.
- Legacy single-machine form: top-level `"host"` (+ optional `"remote_dir"`) becomes a machine if no machine has that host (`Config.swift:76-80`). Encode never writes `host`/`remote_dir` at the top level (`Config.swift:83-89`).
- Save: pretty-printed, sorted keys, no escaped slashes, creates the parent dir (`Config.swift:128-136`). Go: `json.MarshalIndent` with 2 spaces; sorted keys via a map or field order alphabetical; `SetEscapeHTML(false)`.
- `defaultMachine` = machine named by `default`, else the first machine (`Config.swift:97-99`). `resolve(host?)`: unknown host → `unknown machine <h>; see `+"`sshot machine list`"; none → `no machines configured; run `+"`sshot machine add <ssh-host>`" (`Config.swift:102-111`). `load` with no file → `no config at <path>; run `+"`sshot machine add <ssh-host>`"; bad JSON → `invalid config <path>: <err>`.
- Path: `~/.config/sshot/config.json` on every OS (Windows: `%USERPROFILE%\.config\sshot\config.json` via `os.UserHomeDir`). Env `SSHOT_CONFIG` overrides the full path.
- macOS default `terminal_apps` (`Config.swift:48-56`): `com.apple.Terminal`, `com.googlecode.iterm2`, `com.mitchellh.ghostty`, `com.github.wez.wezterm`, `net.kovidgoyal.kitty`, `org.alacritty`, `dev.warp.Warp-Stable`. Windows defaults (matched case-insensitively later): `WindowsTerminal.exe`, `OpenConsole.exe`, `conhost.exe`, `wezterm-gui.exe`, `alacritty.exe`, `mintty.exe`.
- New keys: `ssh_dir` (string, default `~/.ssh`, `~` expands to the local home), `paste_keys` (default Windows `["ctrl+v","ctrl+shift+v"]`, macOS `["cmd+v"]`, other OS `["ctrl+shift+v"]`). Defaults are omitted from the file unless the user set them? Keep Swift behaviour: write `terminal_apps` and `max_dimension` always; write `ssh_dir`/`paste_keys` only when set (pointer/omitempty).
- Defaults must be injectable for tests: e.g. `DefaultsFor(goos string)`.
- README example config (README.md "Config (Mac)" section) must round-trip.

## Owns (may create or modify)
- `internal/config/**`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- `go.mod`/`go.sum`.

## Steps (each ends in tests + commit + handoff checkpoint)
1. Types, defaults per GOOS, `Load`/`LoadOrEmpty`/`Save`/`Path` with `SSHOT_CONFIG`, legacy decode. Tests for legacy, README round-trip, missing/invalid file messages.
2. `Machine(host)`, `DefaultMachine`, `Resolve`, `SSHDir()` expansion, `PasteKeys()` parsing into a small `Chord{Mods, Key}` type defined here (strings like `ctrl+shift+v`, `cmd+v`; reject unknown modifiers with a clear error). Tests.

## Acceptance (run verbatim before marking done)
- `go test ./internal/config/... -count=1` → `ok`
- `GOOS=windows go vet ./internal/config/... && GOOS=darwin go vet ./internal/config/...` → exits 0

## Out of scope
- CLI commands that edit the config (P1-CLI). Regex compilation of `title_match` (P1-DAEMON).
