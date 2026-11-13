# P1-WINSPIKE: Win32 hook/clipboard/SendInput feasibility spike
Phase: 1  Tier: sonnet  Deps: —  Branch: cross-platform-go/P1-WINSPIKE
Plan: PLAN.md §6 (first risk), §5 P1-WINSPIKE

## Goal
A throwaway Windows program that proves the Win32 approach before the real client is written, and a findings section the Phase 2 packets rely on. Deleted in P3-UNIFY.

## Context (pasted, not linked)
- Use only `golang.org/x/sys/windows` (pre-approved, in go.mod) and `syscall.NewLazyDLL` for user32/kernel32 calls it lacks: `SetWindowsHookExW(WH_KEYBOARD_LL=13)`, `CallNextHookEx`, `GetMessageW` loop on a `runtime.LockOSThread` goroutine, `UnhookWindowsHookEx`, `GetForegroundWindow`, `GetWindowThreadProcessId`, `QueryFullProcessImageNameW`, `GetWindowTextW`, `IsClipboardFormatAvailable`, `EnumClipboardFormats`, `GetClipboardFormatNameW`, `RegisterClipboardFormatW("PNG")`, `SendInput` with `KEYBDINPUT.dwExtraInfo` marker `0x5353484F54`.
- WSL interop runs a cross-compiled `.exe` from the Linux shell (verified 2026-11-13). Agents cannot press keys; the interactive mode is for the user.
- Modes: `-selftest` (non-interactive: install + remove hook, enumerate current clipboard formats with names, print foreground exe and title, print `selftest ok`); default interactive mode: log every Ctrl+V / Ctrl+Shift+V keydown with foreground exe/title/clipboard formats; with `-swallow`, swallow those keydowns when the clipboard has an image and, 300 ms later, put the text `SSHOT-SPIKE-OK` on the clipboard and `SendInput` the same chord marked synthetic (which the hook must let through).

## Owns (may create or modify)
- `spike/winhook/**`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- go.mod with `golang.org/x/sys`.

## Steps (each ends in tests + commit + handoff checkpoint)
1. `-selftest` mode; build and run it via interop.
2. Interactive and `-swallow` modes; write `spike/winhook/README.md` with the exact commands for the user. Stop `blocked: needs-user` asking the user to run it in: Windows Terminal (WSL tab ssh'd to a server), a classic console window, and WezTerm if installed; with a Win+Shift+S screenshot and with an Explorer file copy.
3. After the user reports, write `## Findings` in the handoff answering every question in PLAN.md §5 P1-WINSPIKE, plus recommended `terminal_apps` defaults.

## Acceptance (run verbatim before marking done)
- `S=$(mktemp -d); GOOS=windows go build -o $S/winhook.exe ./spike/winhook && $S/winhook.exe -selftest` → last line `selftest ok`
- `grep -c '^## Findings' ../../handoffs/P1-WINSPIKE.md` (from the packet dir) or `grep -c '^## Findings' docs/plans/cross-platform-go/handoffs/P1-WINSPIKE.md` → `1`

## Out of scope
- Production code, tests beyond the selftest.
