# P1-IMAGE: Image decode/downscale/PNG, DIB, GIF passthrough
Phase: 1  Tier: sonnet  Deps: —  Branch: cross-platform-go/P1-IMAGE
Plan: PLAN.md §3 (Seams), §5 P1-IMAGE

## Goal
A pure-Go `internal/imaging` package that turns whatever a clipboard yields (image bytes, Windows DIB, or an image file path) into upload-ready bytes, matching the Swift client's behaviour.

## Context (pasted, not linked)
- Swift `ClipImage.prepared` (`mac/Sources/sshot/Clipboard.swift:10-20`): file with `.gif` extension → bytes as-is, ext `gif`; anything else → PNG, ext `png`.
- Swift `png(from:maxDimension:)` (`Clipboard.swift:51-79`): if `maxDimension > 0` and the longest edge exceeds it, downscale keeping aspect ratio so the longest edge == maxDimension; else keep size. Apply EXIF orientation for JPEG if cheap (`kCGImageSourceCreateThumbnailWithTransform`); optional.
- Image file extensions (`Clipboard.swift:24`): `png jpg jpeg gif webp tif tiff bmp` (drop `heic`: no pure-Go decoder; `.heic` → error containing `unsupported`). Export this set (`IsImageFile(path) bool`), case-insensitive.
- Type: `type Source struct{ Path string; Data []byte; Format string }` where `Format` ∈ `png`, `tiff`, `dib`, `""` (sniff). Function `Prepare(src Source, maxDimension int) (data []byte, ext string, err error)`.
- Windows `CF_DIB`/`CF_DIBV5` data is a `BITMAPINFOHEADER`/`BITMAPV5HEADER` followed by optional masks/palette and pixels, without the 14-byte `BITMAPFILEHEADER`. Handle 24bpp and 32bpp (BI_RGB and BI_BITFIELDS), bottom-up (positive height) and top-down (negative height). For 32bpp BI_RGB, treat alpha as opaque if all alpha bytes are 0.
- Pre-approved: `golang.org/x/image` (`draw.CatmullRom` for scaling; `bmp`, `tiff`, `webp` decoders). Encode with `image/png`.

## Owns (may create or modify)
- `internal/imaging/**`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- go.mod with `golang.org/x/image`.

## Steps (each ends in tests + commit + handoff checkpoint)
1. `Source`, `IsImageFile`, `Prepare` for PNG/JPEG/BMP/TIFF/WEBP data and files, GIF passthrough, downscale. Tests generate fixtures in code (no binary fixtures except a tiny WEBP if needed).
2. DIB decoding with tests for 24bpp bottom-up, 32bpp BI_BITFIELDS top-down, 32bpp zero-alpha.

## Acceptance (run verbatim before marking done)
- `go test ./internal/imaging/... -count=1` → `ok`

## Out of scope
- Reading any clipboard (platform packets).
