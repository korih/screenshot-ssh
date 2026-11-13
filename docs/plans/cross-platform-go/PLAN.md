# Cross-platform sshot in Go: plan

Status: approved 2026-11-13
Integration branch: `dev/cross-platform-go` from `master`. Rules: [RULES.md](RULES.md). State: [TRACKER.md](TRACKER.md).

## 1. Goal

Today the client side of sshot is macOS-only Swift (`mac/Sources/sshot/*.swift`, ~950 lines), so on
Windows pasting an image into a terminal that is SSH'd into a remote server does nothing useful.
Rewrite the client in Go so one codebase serves Windows and macOS: first ship a Windows client next
to the existing Swift Mac build (release 0.3.0), then port the Mac side to Go and delete Swift
(release 1.0.0). The remote side (`vm/`, bash) stays unchanged and is embedded in the Go binary.

**Definition of done:**
- `go test ./... -count=1` passes on Linux, and the `go` CI jobs pass on `ubuntu-latest`, `windows-latest` and `macos-latest`.
- On Windows: with an image on the clipboard (Win+Shift+S), pressing Ctrl+V or Ctrl+Shift+V in Windows Terminal while SSH'd (from WSL) into a configured machine pastes a path like `/home/u/.cache/sshot/2026-11-20_101500-a1b2.png` that exists on that machine; `sshot.exe doctor` exits 0. (User manual check.)
- On macOS: the Go build does the same with Cmd+V in Terminal/iTerm2/Ghostty; `sshot doctor` exits 0. (User manual check.)
- `test ! -e Package.swift && test ! -d mac` on the final branch; `scripts/build-release.sh` produces `sshot-macos.tar.gz` (universal) and `sshot-windows-{amd64,arm64}.zip` with `.sha256` files.
- A machine installed by the Swift 0.2.x client reports `up to date` from the Go client built from the same `VERSION` and `vm/` (identical version stamp).

## 2. Scope

In:
- Go module `github.com/korih/screenshot-ssh` at the repo root; CLI `cmd/sshot` with the same commands as `mac/Sources/sshot/main.swift:3-20`.
- Platform-neutral core: config, embedded payload, in-process SSH/SFTP, image preparation, remote install/sync, uploader, interceptor logic.
- Windows client: Win32 keyboard hook, clipboard, foreground window, synthetic paste, autostart (HKCU Run), log file, `install.ps1`, release zips.
- macOS client in Go via cgo: CGEventTap, NSPasteboard, Accessibility, LaunchAgent; same plist label, paths and tarball name as today.
- CI and release workflows for all of the above; README.

Out (non-goals):
- Linux desktop (X11/Wayland) client. `native_other.go` returns "unsupported" for the daemon; the CLI (`send FILE`, `machine *`, `doctor`) still builds and runs on Linux.
- Local WSL target (pasting into WSL without SSH already works for the user).
- Rewriting `vm/` in Go or changing remote behaviour.
- SSH features beyond: `HostName`, `User`, `Port`, `IdentityFile`, `IdentitiesOnly`, `UserKnownHostsFile`, `Include`, `Host` patterns. `ProxyJump`/`ProxyCommand` produce a clear "unsupported" error.
- HEIC input (Go has no decoder; it is dropped from the image extension list).
- Code signing/notarisation beyond the existing ad-hoc `codesign --sign -`.

## 3. Design

### Layout

```
go.mod, go.sum, .gitattributes                 orchestrator (shared)
assets.go                package sshotassets: //go:embed VERSION vm   (P1-PAYLOAD)
internal/payload/        stamp, file modes, install/uninstall scripts   (P1-PAYLOAD)
internal/config/         config.json load/save/resolve                  (P1-CONFIG)
internal/sshx/           ssh_config, auth, known_hosts, exec, SFTP, pool (P1-SSH)
internal/sshx/sshtest/   in-process SSH+SFTP test server running bash    (P1-SSH)
internal/imaging/        decode, downscale, PNG encode, DIB, GIF passthrough (P1-IMAGE)
internal/remote/         Remote.install/sync/uninstall/installedStamp, Uploader (P1-REMOTE)
internal/platform/       platform.go: interfaces only                    (P1-DAEMON)
internal/platform/fake/  scriptable fake platform for tests              (P1-DAEMON)
internal/platform/native/ all three files created by P1-DAEMON (windows/darwin as placeholders); P2-WINWIRE owns native_windows.go, P3-MACSVC owns native_darwin.go
internal/platform/windows/ Win32 implementation                         (P2-WIN*)
internal/platform/darwin/  cgo/Obj-C implementation                      (P3-MAC*)
internal/daemon/         interceptor: target selection, upload, paste, restore (P1-DAEMON)
cmd/sshot/               CLI; *_windows.go additions by P2-WINWIRE        (P1-CLI)
spike/winhook/           throwaway Win32 feasibility spike, deleted in P3  (P1-WINSPIKE)
scripts/wintest.sh       build a package's Windows test exe and run it via WSL interop (P1-CI)
```

### Ported behaviour (from Swift, cite for implementers)
- Interceptor: `mac/Sources/sshot/EventTap.swift:76-158`: ignore synthetic and autorepeat events; match the paste chord; frontmost app in `terminal_apps`; clipboard has an image; a machine whose `title_match` matches wins, else the default machine unless the global `title_match` is set and misses; swallow repeats while busy; upload; set clipboard text; post the same chord marked synthetic; after 0.5 s restore the clipboard only if nothing else changed it; on error log, beep, notify, clear busy.
- Startup: sync every machine and resolve its remote dir in the background (`EventTap.swift:58-71`).
- Clipboard image rules: `Clipboard.swift:31-48`: copied image files count; image data counts only when there is no text.
- Upload: `Uploader.swift:33-83`: resolve the remote dir once via `mkdir -p … && cd … && pwd -P`, re-resolve after a failed upload; file name `yyyy-MM-dd_HHmmss-xxxx.ext`.
- Payload: `Payload.swift:14-48` and `mac/Sources/sshot-embed/main.swift:18-26`.
- CLI and doctor: `main.swift`, `LaunchAgent.swift:66-95`.

### Seams
- `internal/platform/platform.go` (P1-DAEMON) is the contract every OS implements:
  ```go
  type Mods uint8 // ModCtrl, ModShift, ModAlt, ModCmd
  type Chord struct { Mods Mods; Key string }            // "ctrl+v", "ctrl+shift+v", "cmd+v"
  type KeyEvent struct { Chord Chord; Repeat, Synthetic bool; Native any }
  type App struct { ID string; PID int }                  // bundle ID on macOS, exe name on Windows
  type Platform interface {
      WaitForPermission(ctx context.Context, log func(string)) error
      RunHook(ctx context.Context, handle func(KeyEvent) (swallow bool)) error // blocks
      Frontmost() (App, error)
      WindowTitle(App) string
      Clipboard() Clipboard
      PostPaste(KeyEvent) error   // re-sends the chord the user pressed, marked synthetic
      Beep(); Notify(msg string)
      Autostart() Autostart
      LogPath() string
  }
  type Clipboard interface {
      HasImage() bool                          // must be fast: called from the hook
      ReadImages() ([]imaging.Source, error)
      Snapshot() (Snapshot, error); Restore(Snapshot) error
      SetText(string) error; ChangeCount() int64
  }
  type Autostart interface { Install(exe string) error; Uninstall() error; State() (string, bool) }
  ```
  Implementers may refine signatures inside their packet; changes to `platform.go` after P1-DAEMON merges go through the orchestrator.
- `imaging.Source{Path string; Data []byte; Format string}` (`Format` ∈ `png`, `tiff`, `dib`, `""`): what a clipboard yields and the uploader consumes.
- `sshx.Pool`: `Get(host) (*Client, error)`; `Client.Run(cmd string, stdin []byte) (string, error)`, `Client.Put(remotePath string, data []byte) error`. Built from config `ssh_dir`.

### Config (`~/.config/sshot/config.json` on every OS; `%USERPROFILE%\.config\sshot\config.json` on Windows)
Backward compatible with today's file (`Config.swift:36-91`, including the legacy single `host`). New keys:
- `ssh_dir` (default `~/.ssh`): where `config`, keys and `known_hosts` are read. On Windows `machine add` offers a WSL distro's `\\wsl.localhost\<distro>\home\<user>\.ssh` when the Windows one cannot reach the host.
- `paste_keys`: default `["ctrl+v","ctrl+shift+v"]` on Windows, `["cmd+v"]` on macOS.
- `terminal_apps` defaults per OS: macOS as `Config.swift:48-56`; Windows (case-insensitive exe names) `WindowsTerminal.exe`, `OpenConsole.exe`, `conhost.exe`, `wezterm-gui.exe`, `alacritty.exe`, `mintty.exe`, adjusted by the P1-WINSPIKE findings.
- Env `SSHOT_CONFIG` overrides the path (tests).

### SSH security model
Strict host key checking against `<ssh_dir>/known_hosts` (hashed entries supported). Unknown host → error telling the user to `ssh <host>` once or run `sshot machine add <host> --accept-new-host-key`, which is the only path that appends to `known_hosts`. Changed key → hard error, never overwritten. Auth order: agent (`SSH_AUTH_SOCK` on Unix; `\\.\pipe\openssh-ssh-agent` on Windows via go-winio), then unencrypted identity files from config/defaults. No passwords or keyboard-interactive prompts. One connection per host, kept alive and reopened on failure (replaces ControlMaster).

### Windows specifics
- Two binaries in the zip from the same source: `sshot.exe` (console CLI) and `sshotw.exe` (`-ldflags -H=windowsgui`, used by the HKCU Run key so no console window appears at login). Daemon logs to `%LOCALAPPDATA%\sshot\sshot.log`; a named mutex keeps it single-instance.
- The low-level hook callback must return fast (Windows drops hooks that exceed `LowLevelHooksTimeout`): only `IsClipboardFormatAvailable`-style checks and foreground lookups run inside it; uploads run elsewhere.
- Synthetic input is tagged through `KEYBDINPUT.dwExtraInfo`.

### macOS specifics
Keep `com.sshot.daemon` as the LaunchAgent label, `~/Library/LaunchAgents/com.sshot.daemon.plist`, `ProgramArguments = [exe, "daemon"]`, and `~/Library/Logs/sshot.log`: `install.sh:12,20-30` and `scripts/install-from-source.sh:8,15-16` read them. The CGEventTap run loop runs on the main OS thread (`runtime.LockOSThread` in `init`).

## 4. Phases and milestones

### Phase 1: Go core (Linux-testable)
Milestone M1: the Go CLI builds for linux/windows/darwin(no cgo), its unit and integration tests pass on Linux, its version stamp equals the Swift binary's in macOS CI, and the Windows hook approach is proven. Proven by: P1-PAYLOAD, P1-CONFIG, P1-SSH, P1-IMAGE, P1-REMOTE, P1-DAEMON, P1-CLI, P1-CI, P1-WINSPIKE.

| ID | Title | Deps | Tier | Owns (main paths) |
|---|---|---|---|---|
| P1-PAYLOAD | Embedded vm/ payload and Swift-identical stamp | — | sonnet | `assets.go`, `internal/payload/**`, `scripts/payload-stamp.sh` |
| P1-CONFIG | Config load/save, legacy format, per-OS defaults | — | sonnet | `internal/config/**` |
| P1-SSH | In-process SSH/SFTP pool, ssh_config, agent, known_hosts, test server | — | opus (security-critical: auth and host-key verification) | `internal/sshx/**` |
| P1-IMAGE | Image decode/downscale/PNG, DIB, GIF passthrough | — | sonnet | `internal/imaging/**` |
| P1-REMOTE | Remote install/sync/uninstall and uploader | P1-PAYLOAD, P1-SSH | sonnet | `internal/remote/**` |
| P1-DAEMON | Platform interface, fake platform, interceptor logic | P1-CONFIG, P1-IMAGE | sonnet | `internal/platform/platform.go`, `internal/platform/fake/**`, `internal/platform/native/**` (P2/P3 take over their OS file), `internal/daemon/**` |
| P1-CLI | `cmd/sshot`: all commands and doctor | P1-REMOTE, P1-DAEMON | sonnet | `cmd/sshot/**` |
| P1-CI | Go CI on 3 OSes, Swift/Go stamp parity, wintest helper | P1-CLI | sonnet | `.github/workflows/ci.yml`, `scripts/wintest.sh` |
| P1-WINSPIKE | Win32 hook/clipboard/SendInput feasibility spike | — | sonnet | `spike/winhook/**` |

### Phase 2: Windows client → release 0.3.0
Milestone M2: `sshot.exe` intercepts Ctrl+V / Ctrl+Shift+V in Windows terminals and pastes remote paths (user manual check), installs via `install.ps1`, and the release workflow publishes the Swift Mac tarball plus Windows zips. Proven by: P2-WINCLIP, P2-WINHOOK, P2-WINSVC, P2-WINWIRE, P2-WINDIST.

| ID | Title | Deps | Tier | Owns (main paths) |
|---|---|---|---|---|
| P2-WINCLIP | Win32 clipboard: formats, files, snapshot/restore | P1-DAEMON, P1-WINSPIKE, P1-CI | opus (raw Win32 memory/handle handling; a bug corrupts or loses the user's clipboard) | `internal/platform/windows/clipboard*_windows.go` |
| P2-WINHOOK | Keyboard hook, foreground window, SendInput, beep/notify | P1-DAEMON, P1-WINSPIKE, P1-CI | opus (hook threading and timeout rules; input injection) | `internal/platform/windows/{hook,window,input,notify}*_windows.go` |
| P2-WINSVC | Autostart (HKCU Run), single instance, log file | P1-DAEMON, P1-CI | sonnet | `internal/platform/windows/{autostart,instance,logfile}*_windows.go` |
| P2-WINWIRE | Windows platform glue, CLI Windows bits, WSL ssh_dir offer | P2-WINCLIP, P2-WINHOOK, P2-WINSVC, P1-CLI | sonnet | `internal/platform/windows/platform_windows.go`, `internal/platform/native/native_windows.go`, `cmd/sshot/*_windows.go` (new files only) |
| P2-WINDIST | install.ps1, release build/workflow, README Windows section | P2-WINWIRE, P1-CI | sonnet | `install.ps1`, `scripts/build-release.sh`, `.github/workflows/release.yml`, `.github/workflows/ci.yml`, `README.md`, `vm/claude-commands/shot.md` |

### Phase 3: macOS in Go, Swift removed → release 1.0.0
Milestone M3: the Go Mac build replaces Swift (user manual check), Swift sources are deleted, CI and release build everything from Go. Proven by: P3-MACCLIP, P3-MACHOOK, P3-MACSVC, P3-UNIFY, P3-DOCS.

| ID | Title | Deps | Tier | Owns (main paths) |
|---|---|---|---|---|
| P3-MACCLIP | NSPasteboard via cgo: types, file URLs, snapshot/restore | P1-DAEMON, P1-CI | opus (Obj-C/cgo memory management) | `internal/platform/darwin/clipboard_darwin.*` |
| P3-MACHOOK | CGEventTap, Accessibility, frontmost app/title, synthetic paste | P1-DAEMON, P1-CI | opus (main-thread run loop + cgo callbacks) | `internal/platform/darwin/{eventtap,app,input,notify}_darwin.*` |
| P3-MACSVC | LaunchAgent, darwin glue, macOS CI job for Go darwin tests | P3-MACCLIP, P3-MACHOOK, P1-CLI, P2-WINDIST | sonnet | `internal/platform/darwin/{launchagent,platform}_darwin.go`, `internal/platform/native/native_darwin.go`, `.github/workflows/ci.yml` |
| P3-UNIFY | Delete Swift and spike; Go-only build, install, release | P3-MACSVC | sonnet | `Package.swift`, `mac/**`, `spike/**`, `scripts/*.sh`, `install.sh`, `.github/workflows/*.yml` |
| P3-DOCS | Cross-platform README | P3-UNIFY | haiku | `README.md` |

P3-MACCLIP and P3-MACHOOK: `cross-phase: ok` (they depend only on Phase 1 packets and may run during Phase 2).

## 5. Acceptance by packet

`$S` below is a fresh temp dir (`S=$(mktemp -d)`). `scripts/wintest.sh` exists from P1-CI on.

### P1-PAYLOAD
- `go test ./internal/payload/... -count=1` → `ok`
- `go test ./internal/payload -run 'TestStampMatchesShell|TestExecModesMatchGit|TestInstallScriptInstalls' -v -count=1 | grep -c '^--- PASS'` → `3`
- `scripts/payload-stamp.sh | grep -Eq '^0\.2\.0\+[0-9a-f]{10}$' && echo OK` → `OK`
- `shellcheck scripts/payload-stamp.sh` → exits 0

### P1-CONFIG
- `go test ./internal/config/... -count=1` → `ok` (covers: README example round-trip, legacy `host` config, unknown keys preserved or ignored without error, per-OS defaults via injected GOOS, `ssh_dir` `~` expansion, `paste_keys` parsing, `SSHOT_CONFIG` override)
- `GOOS=windows go vet ./internal/config/... && GOOS=darwin go vet ./internal/config/...` → exits 0

### P1-SSH
- `go test ./internal/sshx/... -count=1` → `ok` (covers: key auth via identity file; via agent keyring; unknown host rejected with an error mentioning `known_hosts`; changed host key rejected; `AcceptNewHostKey` appends exactly one line; hashed known_hosts entry accepted; ssh_config `HostName`/`User`/`Port`/`IdentityFile`/`Include` resolution; `ProxyJump` → error containing `unsupported`; `Run` with stdin; `Put` writes bytes; client reconnects after the server closes the connection)
- `go test ./internal/sshx -run TestNoPasswordAuth -v -count=1 | grep -c '^--- PASS'` → `1`
- `GOOS=windows go vet ./internal/sshx/... && GOOS=darwin go vet ./internal/sshx/...` → exits 0

### P1-IMAGE
- `go test ./internal/imaging/... -count=1` → `ok` (covers: 4000×1000 PNG → 2000×500; `max_dimension` 0 keeps size; GIF file passthrough keeps bytes; DIB 32bpp BI_BITFIELDS and 24bpp bottom-up decode to the expected pixels; JPEG/BMP/TIFF/WEBP decode; `.heic` → error containing `unsupported`)

### P1-REMOTE
- `go test ./internal/remote/... -count=1` → `ok` (against `sshtest` with a temp HOME: install writes `~/.local/share/sshot/version` = stamp; `Sync` returns current then installed after `--force`; uninstall removes it; remote dir `~/.cache/sshot` resolves to an absolute path; upload returns a path matching `^/.+/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}-[0-9a-f]{4}\.png$` whose file exists with the uploaded bytes; a failed upload clears the cached dir)

### P1-DAEMON
- `go test ./internal/daemon/... ./internal/platform/... -count=1` → `ok` (fake-platform scenarios: non-terminal app passes; text clipboard passes; synthetic passes; autorepeat passes; image + terminal swallows, uploads, sets text, posts the same chord, restores after the delay when unchanged; does not restore when changed; repeats swallowed while busy; machine `title_match` routing; global `title_match` miss passes; upload error → beep + notify + busy cleared)
- `go build ./... && GOOS=windows go build ./... && GOOS=darwin CGO_ENABLED=0 go build ./...` → exits 0

### P1-CLI
- `go build -o $S/sshot ./cmd/sshot && $S/sshot help | grep -c 'machine add'` → `1`
- `[ "$($S/sshot version)" = "sshot $(scripts/payload-stamp.sh)" ] && echo SAME` → `SAME`
- `go test ./cmd/sshot/... -count=1` → `ok` (against `sshtest`: `machine add` (with `--accept-new-host-key`), `list` shows `up to date`, `sync`, `default`, `remove`; `send FILE` prints a remote path; `doctor` reports each machine; `daemon` on Linux exits non-zero with `unsupported`)
- `GOOS=windows go build ./... && GOOS=darwin CGO_ENABLED=0 go build ./...` → exits 0

### P1-CI
- `shellcheck scripts/wintest.sh` → exits 0
- `scripts/wintest.sh ./internal/config` → last line `PASS`, exits 0
- After the user pushes the packet branch: `gh run list -R korih/screenshot-ssh --branch cross-platform-go/P1-CI --workflow ci --limit 1 --json conclusion -q '.[0].conclusion'` → `success` (jobs: existing `build` and `shell`; new `go` matrix on ubuntu/windows/macos running `gofmt -l`, `go vet ./...`, `go test ./... -count=1`; new `stamp-parity` on macOS asserting Swift `sshot version` = Go `sshot version`)

### P1-WINSPIKE
- `GOOS=windows go build -o $S/winhook.exe ./spike/winhook && $S/winhook.exe -selftest` → last line `selftest ok` (installs and removes a WH_KEYBOARD_LL hook, enumerates clipboard formats, reads the foreground window's exe and title)
- Handoff contains a `## Findings` section answering: foreground exe for Windows Terminal, conhost and WezTerm windows; whether swallowing Ctrl+V in the hook stops the terminal's paste; whether `SendInput` Ctrl+V/Ctrl+Shift+V with `dwExtraInfo` pastes text into an SSH session; which clipboard formats a Win+Shift+S screenshot and an Explorer file copy expose. Answers come from the user's manual run (`blocked: needs-user` until then).

### P2-WINCLIP
- `GOOS=windows go vet ./internal/platform/windows/...` → exits 0
- `scripts/wintest.sh ./internal/platform/windows -run Clipboard` → `PASS` (sets a PNG, a DIB, a file drop and text; checks `HasImage`/`ReadImages`; snapshot → overwrite → restore gives back identical bytes for every format; `ChangeCount` increases on writes; the test restores the user's original clipboard)

### P2-WINHOOK
- `GOOS=windows go vet ./internal/platform/windows/...` → exits 0
- `scripts/wintest.sh ./internal/platform/windows -run 'Hook|Window|Chord'` → `PASS` (hook installs and uninstalls on a locked thread with a message loop; `Frontmost` returns a non-empty exe name; chord ↔ virtual-key conversion; synthetic-marker detection; no `SendInput` unless `SSHOT_WIN_INPUT_TESTS=1`)

### P2-WINSVC
- `scripts/wintest.sh ./internal/platform/windows -run 'Autostart|Instance|LogFile'` → `PASS` (uses a test value name under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` and deletes it; second instance mutex is refused)

### P2-WINWIRE
- `GOOS=windows go build -o $S/sshot.exe ./cmd/sshot && GOOS=windows go build -ldflags=-H=windowsgui -o $S/sshotw.exe ./cmd/sshot` → exits 0
- `[ "$($S/sshot.exe version | tr -d '\r')" = "sshot $(scripts/payload-stamp.sh)" ] && echo SAME` → `SAME`
- `scripts/wintest.sh ./cmd/sshot` → `PASS`
- User manual check (gate), recorded in the handoff: `sshot.exe machine add <host>` succeeds, `sshot.exe doctor` exits 0, Win+Shift+S then Ctrl+V in Windows Terminal SSH'd into `<host>` pastes an existing remote path, plain text paste is unchanged, and the clipboard image is back afterwards.

### P2-WINDIST
- `scripts/build-release.sh windows && (cd dist && sha256sum -c sshot-windows-amd64.zip.sha256 sshot-windows-arm64.zip.sha256)` → both `OK`
- `unzip -l dist/sshot-windows-amd64.zip | grep -cE ' (sshot|sshotw)\.exe$'` → `2`
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1 -ZipPath "$(wslpath -w dist/sshot-windows-amd64.zip)" -InstallDir "$(wslpath -w $S)" -NoAutostart` → output contains `installed`; then `$S/sshot.exe version` → matches `sshot 0.2.0+`
- `shellcheck install.sh scripts/*.sh vm/install.sh vm/uninstall.sh vm/sshot` → exits 0
- `grep -c 'install.ps1' README.md` → ≥ 1
- After push: `gh run list -R korih/screenshot-ssh --branch cross-platform-go/P2-WINDIST --workflow ci --limit 1 --json conclusion -q '.[0].conclusion'` → `success`

### P3-MACCLIP
- `gofmt -l internal/platform/darwin` → empty; `GOOS=darwin CGO_ENABLED=0 go build ./...` → exits 0
- After push: CI `go` job on macos-latest runs `go test ./internal/platform/darwin -run Clipboard -count=1` → the run concludes `success` (same `gh run list` form as above, branch `cross-platform-go/P3-MACCLIP`)

### P3-MACHOOK
- `gofmt -l internal/platform/darwin` → empty; `GOOS=darwin CGO_ENABLED=0 go build ./...` → exits 0
- After push: CI on macos-latest runs `go test ./internal/platform/darwin -run 'Chord|Frontmost|Marker' -count=1` → `success`

### P3-MACSVC
- `GOOS=darwin CGO_ENABLED=0 go build ./...` → exits 0
- After push: CI `go` job (macOS) builds `CGO_ENABLED=1` for arm64 and amd64, runs `go test ./... -count=1`, and `stamp-parity` passes → `success`
- User manual check (gate), recorded in the handoff: on the user's Mac, the Go build installed over the Swift one keeps `~/Library/LaunchAgents/com.sshot.daemon.plist`, `sshot doctor` exits 0, Cmd+V with a screenshot in Terminal/iTerm2/Ghostty pastes a remote path, text paste unchanged, `sshot machine list` shows `up to date` without reinstalling.

### P3-UNIFY
- `test ! -e Package.swift && test ! -d mac && test ! -d spike && echo GONE` → `GONE`
- `grep -rniE 'swift|xcode' scripts install.sh .github` → no output
- `go test ./... -count=1 && shellcheck install.sh scripts/*.sh vm/install.sh vm/uninstall.sh vm/sshot` → exits 0
- `scripts/build-release.sh windows` → produces both zips (Linux)
- After push: CI `success`; the CI artifact `sshot-macos.tar.gz` contains `sshot` for which `lipo -info` (printed in the job log) lists `x86_64 arm64`

### P3-DOCS
- `grep -c -i 'windows' README.md` → ≥ 3
- `grep -niE 'swift build|xcode' README.md` → no output
- `grep -c 'install.ps1' README.md` → ≥ 1

## 6. Risks and spikes
- **Win32 hook behaviour in terminals** (does swallowing work, which exe owns the window, does SendInput paste into WSL ssh): P1-WINSPIKE, with a user manual run, before P2-WINCLIP/P2-WINHOOK start.
- **Version stamp drift between Swift and Go** (machines would reinstall on every switch): `scripts/payload-stamp.sh` reference plus the `stamp-parity` CI job (P1-CI). `.gitattributes` forces LF in `vm/` and `VERSION` so a Windows checkout hashes the same.
- **`go:embed` drops file modes**: P1-PAYLOAD keeps an explicit executable set and a test comparing it to `git ls-files -s vm`.
- **No Mac available to agents**: Mac code is verified only by pushed CI runs (user gate per push) and the user's manual check before P3-UNIFY deletes Swift.
- **Accessibility grant is tied to the binary**: replacing the Swift binary with Go needs a re-grant; P3-MACSVC's manual check covers it and P3-DOCS documents it.
- **Keys in WSL, daemon in Windows**: `ssh_dir` pointing at `\\wsl.localhost\…\.ssh` needs the distro running and unencrypted keys or the Windows agent; `doctor` reports which source was used.
- **Clipboard tests touch the real Windows clipboard**: tests snapshot and restore it; input-injection tests are opt-in.

## 7. Decision log
| Date | Decision | Reason |
|---|---|---|
| 2026-11-13 | Go, single codebase; Swift removed at the end | User choice; good SSH libs, `go:embed`, no-cgo Windows build |
| 2026-11-13 | Windows target is SSH machines only; no local-WSL target | User: pasting into local WSL already works; SSH sessions are the failure |
| 2026-11-13 | In-process SSH (x/crypto/ssh + SFTP), connection pool | User choice; Windows OpenSSH has no ControlMaster |
| 2026-11-13 | Configurable `ssh_dir`, default `~/.ssh`, offer WSL's `.ssh` | User choice; their keys live in WSL |
| 2026-11-13 | Intercept Ctrl+V and Ctrl+Shift+V on Windows (`paste_keys`) | User choice; Windows Terminal binds both |
| 2026-11-13 | User has a Mac; Mac packets verified by macOS CI + manual check | User choice |
| 2026-11-13 | `install.ps1` + release zips; HKCU Run autostart | User choice |
| 2026-11-13 | Pre-approved deps: x/crypto, x/sys, x/image, pkg/sftp, kevinburke/ssh_config, Microsoft/go-winio | User choice |
| 2026-11-13 | 0.3.0 = Swift Mac + Go Windows; 1.0.0 = Go only | User choice |
| 2026-11-13 | `vm/` stays bash, embedded unchanged | User choice; remotes and mixed clients keep working |
| 2026-11-13 | Linux desktop client is a non-goal | User choice |
| 2026-11-13 | Strict known_hosts; opt-in `--accept-new-host-key` on `machine add` | Assumed (security default, mirrors BatchMode behaviour) |
| 2026-11-13 | Windows ships `sshot.exe` + `sshotw.exe` (GUI subsystem for autostart) | Assumed (avoids a console window at login) |
| 2026-11-13 | HEIC input dropped; ProxyJump/ProxyCommand unsupported with clear errors | Assumed (no pure-Go decoder; keeps SSH scope bounded) |
| 2026-11-13 | Config path `~/.config/sshot/config.json` on every OS | Assumed (parity, simple docs) |
| 2026-11-13 | Plan approved; push `dev/cross-platform-go` to origin and open a linked Forgejo issue | User: "when you are done just push the plan and the remote branch to remote", "also create an issue and link it to the branch" |
