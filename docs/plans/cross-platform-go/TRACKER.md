# Cross-platform sshot in Go: tracker

Single source of truth for the orchestrator. Resume with `/release run docs/plans/cross-platform-go`.

Status: running
Integration branch: `dev/cross-platform-go`. Packet branches `cross-platform-go/<ID>` in `.claude/worktrees/cross-platform-go-<ID>`.

**States:** `todo` (deps not merged) → `ready` → `active` → `review` → `merged`; also `parked` (waiting on the user) and `blocked` (failed review twice).

## Known failures
- none (baseline: no Go code; shellcheck clean on master 42d81fd)

## Packets

### Phase 1: Go core
| ID | Title | Deps | Tier | Owns | State | Merge SHA |
|---|---|---|---|---|---|---|
| P1-PAYLOAD | Embedded vm/ payload and Swift-identical stamp | — | sonnet | `assets.go`, `internal/payload/**`, `scripts/payload-stamp.sh` | ready | |
| P1-CONFIG | Config load/save, legacy format, per-OS defaults | — | sonnet | `internal/config/**` | ready | |
| P1-SSH | In-process SSH/SFTP pool, ssh_config, agent, known_hosts, test server | — | opus | `internal/sshx/**` | ready | |
| P1-IMAGE | Image decode/downscale/PNG, DIB, GIF passthrough | — | sonnet | `internal/imaging/**` | ready | |
| P1-REMOTE | Remote install/sync/uninstall and uploader | P1-PAYLOAD, P1-SSH | sonnet | `internal/remote/**` | todo | |
| P1-DAEMON | Platform interface, fake platform, interceptor logic | P1-CONFIG, P1-IMAGE | sonnet | `internal/platform/platform.go`, `internal/platform/fake/**`, `internal/platform/native/**` (P2/P3 take over their OS file), `internal/daemon/**` | todo | |
| P1-CLI | `cmd/sshot`: all commands and doctor | P1-REMOTE, P1-DAEMON | sonnet | `cmd/sshot/**` | todo | |
| P1-CI | Go CI on 3 OSes, Swift/Go stamp parity, wintest helper | P1-CLI | sonnet | `.github/workflows/ci.yml`, `scripts/wintest.sh` | todo | |
| P1-WINSPIKE | Win32 hook/clipboard/SendInput feasibility spike | — | sonnet | `spike/winhook/**` | ready | |

### Phase 2: Windows client → 0.3.0
| ID | Title | Deps | Tier | Owns | State | Merge SHA |
|---|---|---|---|---|---|---|
| P2-WINCLIP | Win32 clipboard | P1-DAEMON, P1-WINSPIKE, P1-CI | opus | `internal/platform/windows/clipboard*_windows.go` | todo | |
| P2-WINHOOK | Keyboard hook, foreground window, SendInput, beep/notify | P1-DAEMON, P1-WINSPIKE, P1-CI | opus | `internal/platform/windows/{hook,window,input,notify}*_windows.go` | todo | |
| P2-WINSVC | Autostart, single instance, log file | P1-DAEMON, P1-CI | sonnet | `internal/platform/windows/{autostart,instance,logfile}*_windows.go` | todo | |
| P2-WINWIRE | Windows glue, CLI Windows bits, WSL ssh_dir offer | P2-WINCLIP, P2-WINHOOK, P2-WINSVC, P1-CLI | sonnet | `internal/platform/windows/platform_windows.go`, `internal/platform/native/native_windows.go`, `cmd/sshot/*_windows.go` (new) | todo | |
| P2-WINDIST | install.ps1, release build/workflow, README | P2-WINWIRE, P1-CI | sonnet | `install.ps1`, `scripts/build-release.sh`, `.github/workflows/{release,ci}.yml`, `README.md`, `vm/claude-commands/shot.md` | todo | |

### Phase 3: macOS in Go, Swift removed → 1.0.0
| ID | Title | Deps | Tier | Owns | State | Merge SHA |
|---|---|---|---|---|---|---|
| P3-MACCLIP | NSPasteboard via cgo | P1-DAEMON, P1-CI | opus | `internal/platform/darwin/clipboard_darwin.*` | todo | |
| P3-MACHOOK | CGEventTap, Accessibility, frontmost, synthetic paste | P1-DAEMON, P1-CI | opus | `internal/platform/darwin/{eventtap,app,input,notify}_darwin.*` | todo | |
| P3-MACSVC | LaunchAgent, darwin glue, macOS CI | P3-MACCLIP, P3-MACHOOK, P1-CLI, P2-WINDIST | sonnet | `internal/platform/darwin/{launchagent,platform}_darwin.go`, `internal/platform/native/native_darwin.go`, `.github/workflows/ci.yml` | todo | |
| P3-UNIFY | Delete Swift and spike; Go-only build/install/release | P3-MACSVC | sonnet | `Package.swift`, `mac/**`, `spike/**`, `scripts/*.sh`, `install.sh`, `.github/workflows/*.yml` | todo | |
| P3-DOCS | Cross-platform README | P3-UNIFY | haiku | `README.md` | todo | |

## Milestones
- [ ] M1 Go core builds for 3 OSes, tests pass, stamp parity with Swift, Win32 approach proven: P1-*
- [ ] M2 Windows client works (manual check), installer and 0.3.0 release artifacts: P2-*
- [ ] M3 Go Mac client replaces Swift (manual check), Swift deleted, 1.0.0 artifacts: P3-*

## Pending user decisions
- (none)

## Holdouts, reservations and one-time actions
- First prep commit (before any packet): `go.mod` (`module github.com/korih/screenshot-ssh`, `go 1.24`) requiring the six pre-approved modules, `go.sum`, `.gitattributes` (`vm/** text eol=lf`, `VERSION text eol=lf`, `*.sh text eol=lf`).
- `VERSION` → `0.3.0` after M2 (prep commit; tag `v0.3.0` is a user gate). `VERSION` → `1.0.0` after M3 (same).
- Manual user checks: P1-WINSPIKE, P2-WINWIRE, P3-MACSVC.
- Forgejo issue tracking this release: https://forgejo.korih.com/k/screenshot-transfer/issues/1 (ref `dev/cross-platform-go`).

## Session log
- 2026-11-13 s1: plan committed, 5 packets ready. Branch pushed to origin; issue #1 opened and linked to the branch.

## Decision log
| Date | Decision | Reason |
|---|---|---|
| 2026-11-13 | Plan approved (see PLAN.md §7) | User asked to push the plan and open a linked issue |
