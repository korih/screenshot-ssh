# sshot

Paste Mac screenshots into Claude Code running on a remote machine over SSH.

Take a screenshot to the clipboard (**Cmd+Ctrl+Shift+4**), then press **Cmd+V** in your SSH
terminal. sshot uploads the image to the VM and pastes its path, e.g.
`/home/linux/.cache/sshot/2026-10-05_171203-a1b2.png`, and Claude reads the image.

```
Mac: Cmd+V in a terminal app ─► clipboard has an image?
       no  → normal paste, untouched
       yes → PNG (downscaled to ≤2000px) ─scp─► VM ~/.cache/sshot/
           → remote path is pasted instead; clipboard image is restored afterwards
```

Uploads reuse a single SSH connection (ControlMaster), so after the first one they take well under a second.

## Install

### VM (where Claude Code runs)
```sh
vm/install.sh
```
Installs `~/.local/bin/sshot`, the `/shot` Claude Code command, and a daily systemd user timer
that deletes screenshots older than 7 days.

### Mac
Requirements: Xcode Command Line Tools (`xcode-select --install`), plus key-based SSH to the VM
with no password prompt (an alias in `~/.ssh/config` is recommended).

```sh
mac/install.sh
```
This builds `sshot`, installs it to `~/.local/bin`, asks for your SSH host, starts the daemon as a
LaunchAgent, and runs `sshot doctor`. When macOS asks, allow **sshot** under
**System Settings → Privacy & Security → Accessibility**. The daemon starts listening as soon as
you grant access.

> After a rebuild the binary's signature changes, so macOS may stop trusting it. If paste stops
> working after an upgrade, remove sshot from the Accessibility list, add it again, and run `sshot install`.

## Usage

| Where | What |
|---|---|
| Mac terminal | **Cmd+V** with an image (or an image file copied in Finder) on the clipboard |
| Mac CLI | `sshot send` uploads the clipboard image; `sshot send a.png b.jpg` uploads files. Both print the remote paths |
| Claude Code on the VM | `/shot` looks at the latest screenshot; `/shot 3` looks at the last three |
| VM shell | `sshot latest [N]`, `sshot clean [--days D]` |

Text paste is unaffected. Image paste in other apps (Slack, Preview, etc.) is unaffected.

## Config (Mac): `~/.config/sshot/config.json`

```json
{
  "host": "vm",
  "remote_dir": "~/.cache/sshot",
  "max_dimension": 2000,
  "terminal_apps": ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"],
  "title_match": "ssh|vm"
}
```

- `host`: an SSH host or alias. Required.
- `terminal_apps`: bundle IDs where Cmd+V is intercepted. The default covers Terminal, iTerm2, Ghostty, WezTerm, kitty, Alacritty and Warp.
- `title_match`: optional regex. When set, interception happens only when the focused window title matches, so local tabs are skipped. Your shell or terminal must put the host in the title.
- `max_dimension`: longest edge in pixels before downscaling. `0` turns downscaling off.

After you edit the config, run `sshot install` to restart the daemon.

## Troubleshooting

- `sshot doctor` checks the config, SSH, the remote dir and the daemon state.
- The daemon log is at `~/Library/Logs/sshot.log`.
- The daemon runs ssh non-interactively (`BatchMode`). If your key has a passphrase, store it in
  the agent or Keychain (`UseKeychain yes` + `AddKeysToAgent yes` in `~/.ssh/config`).
- Uninstall with `sshot uninstall`, then delete `~/.local/bin/sshot`.
