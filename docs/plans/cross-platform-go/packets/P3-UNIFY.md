# P3-UNIFY: Delete Swift and spike; Go-only build, install, release
Phase: 3  Tier: sonnet  Deps: P3-MACSVC  Branch: cross-platform-go/P3-UNIFY
Plan: PLAN.md §1 (Definition of done), §5 P3-UNIFY

## Goal
Remove the Swift client and the spike, and make every build, install and release path use Go, keeping existing users' upgrade path working.

## Context (pasted, not linked)
- Start only when TRACKER shows the P3-MACSVC manual check passed (deletion is a user gate the orchestrator has cleared).
- Delete: `Package.swift`, `mac/` (Sources, Plugins), `spike/`. `.gitignore` is orchestrator-owned: note in the handoff that `.build/` and `.swiftpm/` can be removed from it.
- `scripts/build-release.sh`: default (macOS) builds Go for arm64 and amd64 with `CGO_ENABLED=1`, `lipo -create` → `dist/sshot`, `codesign --force --sign -`, `lipo -info`, `dist/sshot version`, tar to `dist/sshot-macos.tar.gz` (same name and layout: a single `sshot` at the archive root), `.sha256`; `windows` argument unchanged; add `all` that does both on macOS.
- `install.sh`: release path unchanged (downloads `sshot-macos.tar.gz`); source path (`install_from_source`) needs `go` instead of the Xcode CLT check and calls `scripts/install-from-source.sh`. `scripts/install-from-source.sh`: `go build -o "$dest/sshot" ./cmd/sshot` instead of swift; keep the restart logic (`plutil ProgramArguments.0`).
- Existing Swift users run `sshot upgrade`, which runs `install.sh` from master → downloads the release tarball. That must keep working: same asset name, same `sshot` binary inside, same LaunchAgent label.
- Workflows: remove the Swift `build` job and `stamp-parity` from ci.yml (replace `build` with the Go universal build + smoke test: `dist/sshot help`, `dist/sshot version | grep -q "^sshot $(cat VERSION)+"`); release.yml builds mac via Go and windows zips, publishes all.

## Owns (may create or modify)
- `Package.swift`, `mac/**`, `spike/**` (delete)
- `scripts/*.sh`, `install.sh`, `.github/workflows/*.yml`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. Delete Swift and spike; Go-only `build-release.sh` and `install-from-source.sh`; `install.sh` source path.
2. Workflows. Stop `blocked: needs-user` for the push; check CI and the `lipo -info` line in the build job log (`gh run view -R korih/screenshot-ssh <id> --log | grep 'Architectures in the fat file'`).

## Acceptance (run verbatim before marking done)
- `test ! -e Package.swift && test ! -d mac && test ! -d spike && echo GONE` → `GONE`
- `grep -rniE 'swift|xcode' scripts install.sh .github` → no output
- `go test ./... -count=1 && shellcheck install.sh scripts/*.sh vm/install.sh vm/uninstall.sh vm/sshot` → exits 0
- `scripts/build-release.sh windows` → produces both zips
- `gh run list -R korih/screenshot-ssh --branch cross-platform-go/P3-UNIFY --workflow ci --limit 1 --json conclusion -q '.[0].conclusion'` → `success`, and the build log shows `x86_64 arm64`

## Out of scope
- README (P3-DOCS). VERSION bump and tag (orchestrator + user).
