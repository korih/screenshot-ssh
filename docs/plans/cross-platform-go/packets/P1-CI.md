# P1-CI: Go CI on 3 OSes, Swift/Go stamp parity, wintest helper
Phase: 1  Tier: sonnet  Deps: P1-CLI  Branch: cross-platform-go/P1-CI
Plan: PLAN.md §5 P1-CI, §6

## Goal
CI that runs the Go tests on Linux, Windows and macOS, proves the Go and Swift binaries print the same version stamp, and a local helper to run Windows test binaries from WSL.

## Context (pasted, not linked)
- Current `.github/workflows/ci.yml`: jobs `build` (macos-latest: `scripts/build-release.sh`, smoke `dist/sshot help` and `dist/sshot version | grep -q "^sshot $(cat VERSION)+"`, upload artifact) and `shell` (ubuntu: shellcheck + remote-side install test). Keep both unchanged.
- Workflows run on GitHub `korih/screenshot-ssh`, which Forgejo `origin` push-mirrors on every commit. Pre-approved actions: `actions/checkout@v4`, `actions/upload-artifact@v4`, `actions/setup-go@v5` (`go-version-file: go.mod`).
- New job `go`: matrix `ubuntu-latest`, `windows-latest`, `macos-latest`; steps: `gofmt -l` must be empty (ubuntu only), `go vet ./...`, `go test ./... -count=1`. Set `shell: bash` on Windows.
- New job `stamp-parity` (macos-latest): `swift build -c release` then `go build -o go-sshot ./cmd/sshot`; assert `$(swift build -c release --show-bin-path)/sshot version` equals `./go-sshot version`.
- `scripts/wintest.sh <pkg> [go test flags…]`: `GOOS=windows go test -c -o "$tmp/<name>.test.exe" <pkg>` then run it with `-test.v` and the passed flags (translate `-run X` to `-test.run X`), print its output, exit with its status; temp dir cleaned on exit. WSL interop runs `.exe` directly (verified 2026-11-13). Must pass shellcheck.

## Owns (may create or modify)
- `.github/workflows/ci.yml`
- `scripts/wintest.sh`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. `scripts/wintest.sh` and run it on `./internal/config`.
2. `go` and `stamp-parity` jobs. Then stop with `blocked: needs-user` asking the user to push `cross-platform-go/P1-CI`; after the push, check the run.

## Acceptance (run verbatim before marking done)
- `shellcheck scripts/wintest.sh` → exits 0
- `scripts/wintest.sh ./internal/config` → last line `PASS`, exits 0
- `gh run list -R korih/screenshot-ssh --branch cross-platform-go/P1-CI --workflow ci --limit 1 --json conclusion -q '.[0].conclusion'` → `success`

## Out of scope
- Release workflow (P2-WINDIST).
