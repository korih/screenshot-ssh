# P3-MACCLIP: NSPasteboard via cgo
Phase: 3  Tier: opus (Obj-C/cgo memory management)  Deps: P1-DAEMON, P1-CI  Branch: cross-platform-go/P3-MACCLIP  cross-phase: ok
Plan: PLAN.md §3 (Seams, macOS specifics), §5 P3-MACCLIP

## Goal
Implement `platform.Clipboard` on macOS in Go + Objective-C with the same behaviour as the Swift client's `Clipboard`, so the Go Mac build can replace Swift.

## Context (pasted, not linked)
- Swift reference, port 1:1 (`mac/Sources/sshot/Clipboard.swift`):
  - `hasImage` (L31-36): if types contain `.fileURL` → true iff some file URL has an image extension; else if `.string` → false; else `.png` or `.tiff`.
  - `imageFileURLs` (L38-41): `readObjects(forClasses: [NSURL], options: [.urlReadingFileURLsOnly: true])`, filtered by extension (use `imaging.IsImageFile` on the Go side by returning paths).
  - `readImages` (L43-48): files → `Source{Path}`; else `.png` data → `Format:"png"`; else `.tiff` → `Format:"tiff"`; else `clipboard has no image`.
  - `snapshot` (L82-90): deep-copy every `NSPasteboardItem`'s data per type; `restore` (L92-95): `clearContents` then `writeObjects` of the copies.
  - `changeCount` and `setString(_, forType: .string)` after `clearContents` (`EventTap.swift:143-147`).
- Files: `internal/platform/darwin/clipboard_darwin.go` (`//go:build darwin && cgo`, `#cgo CFLAGS: -x objective-c -fobjc-arc`, `#cgo LDFLAGS: -framework AppKit`), `clipboard_darwin.m`, `clipboard_darwin.h`. Return C buffers allocated with `malloc` and free them on the Go side with `C.free`; wrap Obj-C in `@autoreleasepool`. Represent a snapshot as an opaque retained `NSArray*` handle released by a Go finalizer-free explicit `Release` (Restore consumes it).
- Cannot build here (no darwin cgo cross-compile). Verify `gofmt`, `GOOS=darwin CGO_ENABLED=0 go build ./...` (your files must be excluded by the build tag), and CI on macos-latest after the user pushes your branch.
- Tests `clipboard_darwin_test.go` (`-run Clipboard`) use the general pasteboard on the CI runner and restore it.

## Owns (may create or modify)
- `internal/platform/darwin/clipboard_darwin.*` and `clipboard_darwin_test.go`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. Obj-C bridge + Go wrapper for `HasImage`, `ReadImages`, `SetText`, `ChangeCount`.
2. `Snapshot`/`Restore`; tests. Stop `blocked: needs-user` to have the branch pushed; check the macOS CI job.

## Acceptance (run verbatim before marking done)
- `test -z "$(gofmt -l internal/platform/darwin)" && GOOS=darwin CGO_ENABLED=0 go build ./...` → exits 0
- `gh run list -R korih/screenshot-ssh --branch cross-platform-go/P3-MACCLIP --workflow ci --limit 1 --json conclusion -q '.[0].conclusion'` → `success` (the `go` macOS job runs `go test ./...`, which includes `internal/platform/darwin`)

## Out of scope
- Event tap, LaunchAgent, glue.
