# P3-MACHOOK: CGEventTap, Accessibility, frontmost app/title, synthetic paste
Phase: 3  Tier: opus (main-thread run loop + cgo callbacks)  Deps: P1-DAEMON, P1-CI  Branch: cross-platform-go/P3-MACHOOK  cross-phase: ok
Plan: PLAN.md §3 (Seams, macOS specifics), §5 P3-MACHOOK

## Goal
Implement the macOS input side of `platform.Platform` in Go + Objective-C: the Cmd+V event tap, Accessibility permission flow, frontmost app and window title, synthetic paste, beep and notifications.

## Context (pasted, not linked)
- Swift reference (`mac/Sources/sshot/EventTap.swift`):
  - Tap (L38-56): `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, mask: keyDown)`; add the run-loop source to the main run loop in common modes; enable. Failure → `could not create event tap; grant sshot Accessibility access in System Settings > Privacy & Security`.
  - Callback (L73-87): re-enable on `tapDisabledByTimeout`/`tapDisabledByUserInput`; return NULL to swallow.
  - Event fields (L92-99): synthetic iff `eventSourceUserData == 0x5353484F54`; autorepeat `keyboardEventAutorepeat != 0`; modifiers = flags ∩ {cmd, shift, ctrl, alt}; key = `NSEvent(cgEvent:).charactersIgnoringModifiers.lowercased()` (layout-aware).
  - Frontmost (L101-104): `NSWorkspace.shared.frontmostApplication.bundleIdentifier` and pid. Title (L165-175): AX `kAXFocusedWindowAttribute` → `kAXTitleAttribute`.
  - Synthetic paste (`Clipboard.swift:97-107`): `CGEventSource(.combinedSessionState)`, keyDown+keyUp of the original keycode with `.maskCommand`, `eventSourceUserData = marker`, post to `.cghidEventTap`. Keep the original keycode in `KeyEvent.Native`.
  - Permission (`EventTap.swift:191-212`): `AXIsProcessTrustedWithOptions(prompt: true)`; if not trusted, log `waiting for Accessibility permission (System Settings > Privacy & Security > Accessibility)`, notify `Grant sshot Accessibility access in System Settings to enable image paste.`, poll `AXIsProcessTrusted()` every 2 s.
  - Beep `NSSound.beep()`; notify via `osascript -e 'display notification "<msg>" with title "sshot"'` fire-and-forget (`Shell.swift:68-80`, escape `\` and `"`).
- Threading: AppKit and the tap need the main thread. In this package `func init() { runtime.LockOSThread() }`; `RunHook` must be called from the main goroutine (document it; P3-MACSVC and the CLI ensure `daemon` runs there) and runs `[NSApplication sharedApplication]` with activation policy prohibited, then `CFRunLoopRun`/`[NSApp run]`; stop on ctx cancel via `CFRunLoopStop` on the main loop. Callbacks into Go use `//export` functions and a `cgo.Handle`. Keep the Go callback fast; never block the tap.
- Files `internal/platform/darwin/{eventtap,app,input,notify}_darwin.{go,m,h}` with `//go:build darwin && cgo`; frameworks AppKit, ApplicationServices, CoreGraphics.
- Tests run on CI macOS without Accessibility: only `Chord` parsing, `Marker` field round-trip on a created (not posted) CGEvent, and `Frontmost` returning a non-empty bundle ID or a clean error.

## Owns (may create or modify)
- `internal/platform/darwin/{eventtap,app,input,notify}_darwin.*` and their tests

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. Frontmost/title, beep/notify, event field helpers; tests.
2. Permission flow, tap + run loop + ctx stop, `PostPaste`. Stop `blocked: needs-user` to have the branch pushed; check CI.

## Acceptance (run verbatim before marking done)
- `test -z "$(gofmt -l internal/platform/darwin)" && GOOS=darwin CGO_ENABLED=0 go build ./...` → exits 0
- `gh run list -R korih/screenshot-ssh --branch cross-platform-go/P3-MACHOOK --workflow ci --limit 1 --json conclusion -q '.[0].conclusion'` → `success`

## Out of scope
- Clipboard (P3-MACCLIP), LaunchAgent and glue (P3-MACSVC).
