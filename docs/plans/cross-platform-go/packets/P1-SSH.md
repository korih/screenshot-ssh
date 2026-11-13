# P1-SSH: In-process SSH/SFTP pool, ssh_config, agent, known_hosts, test server
Phase: 1  Tier: opus (security-critical: auth and host-key verification)  Deps: —  Branch: cross-platform-go/P1-SSH
Plan: PLAN.md §3 (SSH security model, Seams), §5 P1-SSH

## Goal
Replace the Swift client's `ssh`/`scp` subprocesses with an in-process SSH client that keeps one connection per host (Windows OpenSSH has no ControlMaster), reads the user's ssh config and keys from a configurable directory, and verifies host keys strictly. Also provide an in-process test server that later packets use for integration tests.

## Context (pasted, not linked)
- Swift options today (`mac/Sources/sshot/Uploader.swift:18-31`): ControlMaster/ControlPersist 30m, `BatchMode=yes` (never prompt), `ConnectTimeout=5`, `RemoteCommand=none`, `RequestTTY=no`. Commands run non-interactively with stdin from a buffer (`Shell.swift:56-59`); uploads use scp to `host:/abs/path` (`Uploader.swift:65`).
- Pre-approved modules (already in go.mod): `golang.org/x/crypto/ssh`, `.../ssh/agent`, `.../ssh/knownhosts`, `github.com/pkg/sftp`, `github.com/kevinburke/ssh_config`, `github.com/Microsoft/go-winio` (Windows agent pipe `\\.\pipe\openssh-ssh-agent`).
- API the rest of the code expects: `type Options struct{ SSHDir string; AcceptNewHostKey bool; Timeout time.Duration }`; `NewPool(Options) *Pool`; `(*Pool).Get(host string) (*Client, error)`; `(*Client).Run(cmd string, stdin []byte) (stdout string, err error)` (error includes trimmed stderr and exit status, like `Shell.swift:48-51`: `ssh exited <n>: <stderr>`); `(*Client).Put(remotePath string, data []byte) error`; `(*Pool).Close()`. `host` is an alias or `user@host[:port]`.
- Config resolution from `<SSHDir>/config` (and `Include`d files, relative to SSHDir): `HostName`, `User` (default: local username), `Port` (default 22), `IdentityFile` (default `id_ed25519`, `id_ecdsa`, `id_rsa` in SSHDir; `~` in values means the directory containing SSHDir's parent home, i.e. expand `~/.ssh/x` to `<SSHDir>/x` when SSHDir ends in `.ssh`), `IdentitiesOnly`, `UserKnownHostsFile` (default `<SSHDir>/known_hosts`). `ProxyJump`/`ProxyCommand` set → error containing `unsupported`.
- Host keys: `knownhosts.New`; unknown → error `host key for <host> is not in <file>; run `+"`ssh <host>`"+` once, or `+"`sshot machine add <host> --accept-new-host-key`"; mismatch → hard error, never write. `AcceptNewHostKey` appends exactly one line via `knownhosts.Line` (hashed? write plain `knownhosts.Normalize(addr)` like `accept-new`).
- Auth: agent first (`SSH_AUTH_SOCK` on Unix; go-winio pipe on Windows, in `agent_windows.go`), then identity files that parse without a passphrase. Encrypted key with no agent → error telling the user to add it to the agent. Never configure password or keyboard-interactive callbacks.
- Keepalive: send `keepalive@openssh.com` every 30 s; on failure drop the client so the next `Get` reconnects. `Run`/`Put` retry once on a closed connection.
- `internal/sshx/sshtest`: `Start(t, opts) *Server` with an ed25519 host key, an authorized key list, `Exec` that runs the command with `bash -c` in a given env (HOME override) and stdin, and an SFTP subsystem (`sftp.NewServer`) rooted at `/`; helpers to write a matching `known_hosts` and `config` into a temp SSHDir; `Kill()` to drop connections. P1-REMOTE and P1-CLI depend on this.

## Owns (may create or modify)
- `internal/sshx/**` (including `internal/sshx/sshtest/**`)

## Registry appends allowed
- none

## Already done by orchestrator prep commit
- go.mod with the six pre-approved modules.

## Steps (each ends in tests + commit + handoff checkpoint)
1. `sshtest` server (exec + SFTP + kill) with a self-test.
2. Config resolution and identity/agent auth; tests for each listed directive, ProxyJump error, agent keyring auth via a temp unix socket.
3. Host key policy: unknown, mismatch, hashed entry, accept-new; `TestNoPasswordAuth` asserts the client config has only publickey methods.
4. Pool, `Run` with stdin, `Put` via SFTP, keepalive and reconnect after `Kill()`. Windows agent file compiles (`GOOS=windows go vet`).

## Acceptance (run verbatim before marking done)
- `go test ./internal/sshx/... -count=1` → `ok`
- `go test ./internal/sshx -run TestNoPasswordAuth -v -count=1 | grep -c '^--- PASS'` → `1`
- `GOOS=windows go vet ./internal/sshx/... && GOOS=darwin go vet ./internal/sshx/...` → exits 0

## Out of scope
- Remote install logic and remote dir resolution (P1-REMOTE). Reading sshot's config.json (callers pass SSHDir).
