# P2-WINCLIP: Win32 clipboard
Phase: 2  Tier: opus (raw Win32 memory/handle handling; a bug corrupts or loses the user's clipboard)  Deps: P1-DAEMON, P1-WINSPIKE, P1-CI  Branch: cross-platform-go/P2-WINCLIP
Plan: PLAN.md §3 (Seams, Windows specifics), §5 P2-WINCLIP

## Goal
Implement `platform.Clipboard` on Windows so the daemon can tell whether the clipboard holds an image, read it, replace it with text, and put the user's original contents back.

## Context (pasted, not linked)
- Interface: `internal/platform/platform.go` (P1-DAEMON): `HasImage() bool` (called from the keyboard hook: must not block; use `IsClipboardFormatAvailable` only, no `OpenClipboard`), `ReadImages() ([]imaging.Source, error)`, `Snapshot()`, `Restore(Snapshot)`, `SetText(string)`, `ChangeCount() int64` (`GetClipboardSequenceNumber`).
- Image rules (Swift `mac/Sources/sshot/Clipboard.swift:31-48`): if `CF_HDROP` is present → image iff at least one dropped file has an image extension (`imaging.IsImageFile`), and `ReadImages` returns those files as `Source{Path}`; else if `CF_UNICODETEXT` present → not an image; else image iff registered `"PNG"` format, `CF_DIBV5` or `CF_DIB` is available. Read order: files, `PNG` (`Format:"png"`), `CF_DIBV5`/`CF_DIB` (`Format:"dib"`). Error `clipboard has no image`.
- `HasImage` for `CF_HDROP` needs the file names; reading them requires `OpenClipboard`. Read P1-WINSPIKE handoff `## Findings` for timing; if opening the clipboard in the hook is too slow, treat `CF_HDROP` as "maybe" in `HasImage` and let `ReadImages` decide (the daemon then reports `clipboard has no image` only for non-image file copies; document the choice in the handoff).
- `OpenClipboard` can fail while another app holds it: retry up to 10 times with 20 ms sleeps. Always `CloseClipboard`.
- Snapshot: enumerate formats with `EnumClipboardFormats`; copy every HGLOBAL-backed format's bytes (`GlobalLock`/`GlobalSize`). Skip GDI/handle formats that are not HGLOBAL (`CF_BITMAP`, `CF_ENHMETAFILE`, `CF_METAFILEPICT`, `CF_PALETTE`, `CF_OWNERDISPLAY`, `CF_DSPBITMAP`, `CF_DSPENHMETAFILE`) and synthesized ones Windows recreates (`CF_TEXT`/`CF_OEMTEXT` when `CF_UNICODETEXT` exists, `CF_DIB` when `CF_DIBV5` exists, `CF_LOCALE`). Restore: `EmptyClipboard` then `SetClipboardData` with `GlobalAlloc(GMEM_MOVEABLE)` copies; on failure free the memory you still own.
- `SetText`: `EmptyClipboard` + `CF_UNICODETEXT` UTF-16 NUL-terminated.
- Use `golang.org/x/sys/windows` + `NewLazySystemDLL("user32.dll")`/`kernel32.dll`. Lock the OS thread around open/close.
- Tests run on the real clipboard via `scripts/wintest.sh ./internal/platform/windows -run Clipboard`; each test snapshots the user's clipboard first and restores it in `t.Cleanup`.

## Owns (may create or modify)
- `internal/platform/windows/clipboard_windows.go`, `internal/platform/windows/clipboard_windows_test.go` (and other `clipboard*_windows.go`)

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. Open/close with retry, `SetText`, `ChangeCount`, `HasImage`; tests.
2. `ReadImages` for PNG, DIB, HDROP; tests writing each format then reading it back.
3. `Snapshot`/`Restore`; byte-identical round-trip test across text, PNG, DIBV5, HDROP and a custom registered format.

## Acceptance (run verbatim before marking done)
- `GOOS=windows go vet ./internal/platform/windows/...` → exits 0
- `scripts/wintest.sh ./internal/platform/windows -run Clipboard` → `PASS`

## Out of scope
- Hook, input, glue (other P2 packets).
