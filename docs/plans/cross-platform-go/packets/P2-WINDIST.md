# P2-WINDIST: install.ps1, release build/workflow, README
Phase: 2  Tier: sonnet  Deps: P2-WINWIRE, P1-CI  Branch: cross-platform-go/P2-WINDIST
Plan: PLAN.md §5 P2-WINDIST, §7 (0.3.0 = Swift Mac + Go Windows)

## Goal
Make the Windows client installable and releasable: a PowerShell installer, Windows zips built by the release script and workflow next to the existing Swift Mac tarball, and README instructions.

## Context (pasted, not linked)
- `scripts/build-release.sh` today: Swift universal build on macOS → `dist/sshot`, `dist/sshot-macos.tar.gz`, `.sha256` (via `shasum -a 256`). Keep that as the default (no-arg) behaviour; add a `windows` argument that cross-compiles `GOOS=windows GOARCH={amd64,arm64}` `sshot.exe` and `sshotw.exe` (`-ldflags=-H=windowsgui`) into `dist/sshot-windows-<arch>.zip` + `.zip.sha256` (`sha256sum` format, `shasum -a 256` on macOS). Do not `rm -rf dist` in a way that deletes the other platform's output when both run.
- `.github/workflows/release.yml`: one job on macos-latest checks the tag matches `VERSION`, builds, and `gh release create` with the mac files. Add a `windows` job (ubuntu-latest, setup-go) that builds the zips and uploads them as an artifact; make the publish step wait for both and attach all files.
- `.github/workflows/ci.yml` (after P1-CI): add a step to the ubuntu `go` job running `scripts/build-release.sh windows` and uploading the zips as an artifact.
- `install.ps1` (mirror `install.sh`): params/env `-ZipPath` (local zip, for tests), `-InstallDir`/`SSHOT_INSTALL_DIR` (default `%LOCALAPPDATA%\sshot\bin`), `-NoAutostart`, `SSHOT_FORCE`. Without `-ZipPath`: resolve the latest tag via the `https://github.com/korih/screenshot-ssh/releases/latest` redirect, download `sshot-windows-<arch>.zip` + `.sha256` (arch from `$env:PROCESSOR_ARCHITECTURE`), verify with `Get-FileHash`, skip if `sshot.exe version` already starts with `sshot <tag>+` unless forced. Extract, add InstallDir to the user PATH if missing, print `installed <dir>\sshot.exe (<version>)`; if autostart is set up already, run `sshot.exe install` and `sshot.exe machine sync`; else print `Next: sshot machine add <ssh-host>`. Must work in Windows PowerShell 5.1.
- `install.sh` line 16 refuses non-macOS; leave it (mac-only until P3-UNIFY).
- README: add a "Windows" install/usage section (Ctrl+V / Ctrl+Shift+V, `irm https://raw.githubusercontent.com/korih/screenshot-ssh/master/install.ps1 | iex`, `ssh_dir` for keys in WSL, `--accept-new-host-key`, log path `%LOCALAPPDATA%\sshot\sshot.log`). Change the tagline from Mac-only to "Mac and Windows".
- `vm/claude-commands/shot.md` says "uploaded from my Mac": change to "uploaded from my computer" (this changes the stamp; intended).

## Owns (may create or modify)
- `install.ps1`, `scripts/build-release.sh`, `.github/workflows/release.yml`, `.github/workflows/ci.yml`, `README.md`, `vm/claude-commands/shot.md`

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- none

## Steps (each ends in tests + commit + handoff checkpoint)
1. `build-release.sh windows` + checksums.
2. `install.ps1` tested via interop with `-ZipPath` and a temp `-InstallDir`.
3. Workflows, README, shot.md. Stop `blocked: needs-user` to have the branch pushed; check CI.

## Acceptance (run verbatim before marking done)
- `scripts/build-release.sh windows && (cd dist && sha256sum -c sshot-windows-amd64.zip.sha256 sshot-windows-arm64.zip.sha256)` → both `OK`
- `unzip -l dist/sshot-windows-amd64.zip | grep -cE ' (sshot|sshotw)\.exe$'` → `2`
- `S=$(mktemp -d); powershell.exe -NoProfile -ExecutionPolicy Bypass -File install.ps1 -ZipPath "$(wslpath -w dist/sshot-windows-amd64.zip)" -InstallDir "$(wslpath -w $S)" -NoAutostart` → output contains `installed`; `$S/sshot.exe version` → starts with `sshot 0.2.0+` (or the current VERSION)
- `shellcheck install.sh scripts/*.sh vm/install.sh vm/uninstall.sh vm/sshot` → exits 0
- `grep -c 'install.ps1' README.md` → ≥ 1
- `gh run list -R korih/screenshot-ssh --branch cross-platform-go/P2-WINDIST --workflow ci --limit 1 --json conclusion -q '.[0].conclusion'` → `success`

## Out of scope
- Bumping `VERSION` or tagging (orchestrator + user gate).
