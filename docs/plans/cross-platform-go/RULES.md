# Cross-platform sshot in Go: rules

Every agent on this release reads this file. The orchestrator owns it.

## Commands
- Tests (module scope): `go test ./{module}/... -count=1`
- Tests (full suite): `go test ./... -count=1 && shellcheck install.sh scripts/*.sh vm/install.sh vm/uninstall.sh vm/sshot`
- Windows tests (from P1-CI on): `scripts/wintest.sh ./{module} [-run REGEX]`. Builds `GOOS=windows go test -c` and runs the `.exe` through WSL interop (verified working on this machine 2026-11-13).
- Lint: `test -z "$(gofmt -l $(git ls-files '*.go'))" && go vet ./... && GOOS=windows go vet ./... && GOOS=darwin CGO_ENABLED=0 go vet ./...`
- Type-check: covered by `go vet`/`go build` for all three GOOS values above.
- macOS cgo code cannot be built here. It is verified by GitHub Actions on the mirror: `gh run list -R korih/screenshot-ssh --branch <branch> --workflow ci --limit 1 --json conclusion -q '.[0].conclusion'`. Pushing is a user gate, so the packet stops with `blocked: needs-user` ("push <branch>") and resumes when the run exists.
- Baseline on `master` at 42d81fd, 2026-11-13: no Go code; `shellcheck` on the shell files passes. Toolchain: `go1.26.10 linux/amd64`, `shellcheck` on PATH, `gh` logged in to github.com as korih.

## Repo facts
- `origin` is Forgejo `ssh://git@forgejo.korih.com:30222/k/screenshot-transfer.git`; it push-mirrors every branch on commit to GitHub `korih/screenshot-ssh`, where the workflows in `.github/workflows/` run. README and `install.sh` URLs point at GitHub; keep them.
- Go module path: `github.com/korih/screenshot-ssh`. Minimum `go 1.24` in `go.mod`.
- The Swift sources under `mac/` stay buildable and untouched until P3-UNIFY; they are the reference behaviour.

## Conventions
- Commit message: `[<ID>] <area>: <what changed>`, lowercase, imperative (repo style is short and lowercase, e.g. `workflow fix`).
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Go style: `gofmt`; errors are `fmt.Errorf` with lowercase messages that read like the Swift `SshotError` strings (e.g. `no machines configured; run ` + "`sshot machine add <ssh-host>`"); keep user-facing messages identical to the Swift ones where a Swift equivalent exists.
- OS-specific files use `_windows.go` / `_darwin.go` suffixes or `//go:build` tags; darwin cgo files use `//go:build darwin && cgo` so `GOOS=darwin CGO_ENABLED=0` builds a stub.
- Comments: short, explain why, like the Swift sources. No banner comments.
- Tests: standard `testing` only, no assertion libraries. Tests never touch the real `~/.config/sshot`, `~/.ssh`, or real hosts; use `t.TempDir()`, `SSHOT_CONFIG`, and `internal/sshx/sshtest`.

## Invariants (every change must keep these)
- The version stamp is `VERSION + "+" + first 10 hex of SHA-256` over, for each file under `vm/` sorted by relative path, the UTF-8 relative path followed by the standard padded base64 of its bytes (`mac/Sources/sshot/Payload.swift:14-24`). Go and Swift must print the same `sshot version` for the same tree; otherwise every remote reinstalls on every switch.
- `vm/` behaviour and the remote layout (`~/.local/bin/sshot`, `~/.local/share/sshot/version`, `~/.claude/commands/shot.md`, `~/.cache/sshot`) do not change. Only P2-WINDIST edits a `vm/` file (wording in `shot.md`).
- Config files written by Swift 0.2.x load unchanged, including the legacy single `host` form (`Config.swift:76-80`).
- Host keys are verified strictly against `<ssh_dir>/known_hosts`. Nothing appends to `known_hosts` except `machine add --accept-new-host-key`; nothing ever replaces a changed key. No password or keyboard-interactive auth.
- Text paste and non-terminal apps are never affected: the interceptor passes the event through unless the frontmost app is a configured terminal, the chord is a configured paste key, and the clipboard holds an image (`EventTap.swift:93-122`).
- The user's clipboard is restored after a paste unless something else changed it (`EventTap.swift:142-155`).
- macOS: LaunchAgent label `com.sshot.daemon`, plist `~/Library/LaunchAgents/com.sshot.daemon.plist` with `ProgramArguments = [exe, "daemon"]`, log `~/Library/Logs/sshot.log`, release asset `sshot-macos.tar.gz` containing `sshot`. `install.sh` and existing Swift installs' `sshot upgrade` depend on them.
- Windows input hook callbacks do no I/O beyond clipboard-format and foreground-window queries.
- Tests that call Windows `SendInput` run only with `SSHOT_WIN_INPUT_TESTS=1`. Clipboard tests save and restore the user's clipboard.

## User gates (stop: `blocked: needs-user`)
- Any push, any merge into `master`, any tag or release, any deploy.
- Running sshot against a real host (`machine add`, `sync`, `send`) or installing the daemon/autostart on the user's machine: user runs it or approves it.
- Manual checks named in PLAN.md §5 (P1-WINSPIKE, P2-WINWIRE, P3-MACSVC).
- Deleting the Swift sources (P3-UNIFY starts only after the P3-MACSVC manual check passed).
- Any Go module not in: `golang.org/x/crypto`, `golang.org/x/sys`, `golang.org/x/image`, `github.com/pkg/sftp`, `github.com/kevinburke/ssh_config`, `github.com/Microsoft/go-winio`. Any new GitHub Action not already used (`actions/checkout`, `actions/upload-artifact`) except `actions/setup-go`, which is pre-approved.
- Secrets, signing identities, paid services.

## Shared files (orchestrator only, via `prep:` commits)
- `go.mod`, `go.sum` (packets never run `go get` or `go mod tidy`; the orchestrator adds the pre-approved modules in the first prep commit and tidies after merges)
- `.gitattributes` (prep: `vm/** text eol=lf`, `VERSION text eol=lf`, `*.sh text eol=lf`)
- `.gitignore`, `VERSION`
- `docs/plans/cross-platform-go/**` except a packet's own `handoffs/<ID>.md`

## Limits
- Max concurrent implementers: 3
- Stall threshold: 30 minutes without handoff update or commit
