# P2-WINHOOK: Keyboard hook, foreground window, SendInput, beep/notify
Phase: 2  Tier: opus (hook threading and timeout rules; input injection)  Deps: P1-DAEMON, P1-WINSPIKE, P1-CI  Branch: cross-platform-go/P2-WINHOOK
Plan: PLAN.md §3 (Seams, Windows specifics), §5 P2-WINHOOK

## Goal
Implement the Windows input side of `platform.Platform`: a low-level keyboard hook that reports paste chords and can swallow them, frontmost app and window title, re-sending the chord as synthetic input, and beep/notify.

## Context (pasted, not linked)
- Interface methods (P1-DAEMON `internal/platform/platform.go`): `RunHook(ctx, handle func(KeyEvent) bool) error`, `Frontmost() (App, error)` (App.ID = exe base name, e.g. `WindowsTerminal.exe`), `WindowTitle(App) string`, `PostPaste(KeyEvent) error`, `Beep()`, `Notify(msg)`, `WaitForPermission` (no-op on Windows).
- Read P1-WINSPIKE's `spike/winhook/` code and handoff `## Findings` first; reuse what worked.
- Hook: `SetWindowsHookExW(WH_KEYBOARD_LL)` on a goroutine with `runtime.LockOSThread` and a `GetMessageW` loop; stop on ctx cancel by posting `WM_QUIT` to that thread (`PostThreadMessageW`). Only `WM_KEYDOWN`/`WM_SYSKEYDOWN` are reported. Return 1 to swallow, else `CallNextHookEx`.
- The callback must return well under `LowLevelHooksTimeout` (Windows silently removes slow hooks): `handle` must only do fast checks (clipboard format availability, foreground lookup). Document this on `RunHook`.
- Modifiers: from `GetAsyncKeyState(VK_CONTROL/VK_SHIFT/VK_MENU/VK_LWIN|VK_RWIN)` at callback time. Key: `vkCode` 'V' (0x56) → `"v"`. Autorepeat: track keys currently down (keydown without an intervening keyup = repeat). Synthetic: `KBDLLHOOKSTRUCT.dwExtraInfo == 0x5353484F54` (same marker value as `Clipboard.swift:27`); also `LLKHF_INJECTED` without the marker counts as not ours (pass, Synthetic=false).
- `PostPaste(ev)`: `SendInput` keydown of each modifier in ev.Chord, 'V' down, 'V' up, modifiers up, all with `dwExtraInfo` marker. Release any physically held modifiers not in the chord? Keep simple: send exactly the chord.
- Frontmost: `GetForegroundWindow` → `GetWindowThreadProcessId` → `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` → `QueryFullProcessImageNameW` → base name. Title: `GetWindowTextW`.
- Beep: `MessageBeep(MB_ICONERROR)`. Notify: best effort, non-blocking; run `powershell -NoProfile -WindowStyle Hidden -Command` with a short Windows.UI.Notifications toast script, ignore failures (Swift equivalent `Shell.swift:68-75` is fire-and-forget).
- Tests via `scripts/wintest.sh ./internal/platform/windows -run 'Hook|Window|Chord'`; anything calling `SendInput` is skipped unless `SSHOT_WIN_INPUT_TESTS=1`.

## Owns (may create or modify)
- `internal/platform/windows/{hook,window,input,notify}*_windows.go` and their `_test.go` files

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. Frontmost exe + title; chord/vk conversion; tests.
2. Hook thread with ctx shutdown, repeat and synthetic detection; tests install, feed nothing, and shut down cleanly within 1 s.
3. `PostPaste`, `Beep`, `Notify`; input test gated by `SSHOT_WIN_INPUT_TESTS=1`.

## Acceptance (run verbatim before marking done)
- `GOOS=windows go vet ./internal/platform/windows/...` → exits 0
- `scripts/wintest.sh ./internal/platform/windows -run 'Hook|Window|Chord'` → `PASS`

## Out of scope
- Clipboard (P2-WINCLIP), autostart (P2-WINSVC), the `Platform` struct glue (P2-WINWIRE).
