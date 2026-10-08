# sshot

Paste Mac screenshots into Claude Code running on remote machines over SSH.

Take a screenshot to the clipboard (**Cmd+Ctrl+Shift+4**), then press **Cmd+V** in your SSH
terminal. sshot uploads the image to the machine and pastes its path, e.g.
`/home/linux/.cache/sshot/2026-10-05_171203-a1b2.png`, and Claude reads the image.

```
Mac: Cmd+V in a terminal app ─► clipboard has an image?
       no  → normal paste, untouched
       yes → PNG (downscaled to ≤2000px) ─scp─► machine ~/.cache/sshot/
           → remote path is pasted instead; clipboard image is restored afterwards
```

Uploads reuse a single SSH connection (ControlMaster), so after the first one they take well under a second.

## Install

Everything ships as one Mac binary. It carries the remote side and installs it over SSH, so
nothing needs to be cloned or built on the remote machine.

Requirements: the Xcode Command Line Tools (`xcode-select --install`) and key-based SSH to each
machine with no password prompt (an alias in `~/.ssh/config` is recommended).

```sh
curl -fsSL https://forgejo.korih.com/k/screenshot-transfer/raw/branch/master/install.sh | sh
```

The installer clones the repo to `~/.local/share/sshot/src`, builds it (a few seconds), and
installs `~/.local/bin/sshot`. Set `SSHOT_REF` to build a branch or tag other than `master`.

Then add each machine where Claude Code runs:

```sh
sshot machine add linux            # an alias from ~/.ssh/config
sshot machine add me@10.0.0.5      # or user@host
```

`machine add` needs key-based SSH with no password prompt. It installs `~/.local/bin/sshot`, the
`/shot` Claude Code command and a daily cleanup timer on the machine, then starts the Mac daemon.
When macOS asks, allow **sshot** under **System Settings → Privacy & Security → Accessibility**.

### Versions stay in sync

The Mac is the source of truth. Each machine records the version it got in
`~/.local/share/sshot/version`, and the Mac brings it up to date whenever:

- the daemon starts (login, `sshot install`, any `sshot machine` change),
- you run `sshot upgrade` (or re-run the installer), which pulls and rebuilds the source,
- you run `sshot machine sync`.

`sshot machine list` and `sshot doctor` show each machine's version. The version is `VERSION`
plus a hash of `vm/`, so a local build with edited remote files counts as a new version too.

> macOS ties the Accessibility grant to the exact binary. After an upgrade that rebuilt sshot, if Cmd+V stops
> working, remove sshot from the Accessibility list, add it again, and run `sshot install`.

### Several machines

The first machine you add is the default. Cmd+V uploads to the default machine unless another
machine's `title_match` matches the focused terminal window title:

```sh
sshot machine add gpu-box --title 'gpu-box'
sshot machine default linux
sshot send -m gpu-box shot.png
```

## Usage
## Usage

| Where | What |
|---|---|
| Mac terminal | **Cmd+V** with an image (or an image file copied in Finder) on the clipboard |
| Mac CLI | `sshot send` uploads the clipboard image; `sshot send a.png b.jpg` uploads files. Both print the remote paths. `-m <host>` picks a machine |
| Mac CLI | `sshot machine add/remove/list/sync/default`, `sshot upgrade`, `sshot version`, `sshot doctor` |
| Claude Code on the machine | `/shot` looks at the latest screenshot; `/shot 3` looks at the last three |
| Remote shell | `sshot latest [N]`, `sshot clean [--days D]`, `sshot version` |

Text paste is unaffected. Image paste in other apps (Slack, Preview, etc.) is unaffected.

## Config (Mac): `~/.config/sshot/config.json`

`sshot machine` commands manage this file. You can also edit it by hand.

```json
{
  "machines": [
    { "host": "linux", "remote_dir": "~/.cache/sshot" },
    { "host": "gpu-box", "remote_dir": "~/.cache/sshot", "title_match": "gpu-box" }
  ],
  "default": "linux",
  "max_dimension": 2000,
  "terminal_apps": ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"],
  "title_match": "ssh"
}
```

- `machines[].host`: an SSH host or alias.
- `machines[].title_match`: optional regex. Sends Cmd+V to this machine when the focused window title matches.
- `default`: machine used when no machine's `title_match` matches.
- `terminal_apps`: bundle IDs where Cmd+V is intercepted. The default covers Terminal, iTerm2, Ghostty, WezTerm, kitty, Alacritty and Warp.
- `title_match`: optional regex. When set, interception happens only when the focused window title
  matches it (or a machine's `title_match`), so local tabs are skipped. Your shell or terminal must put the host in the title.
- `max_dimension`: longest edge in pixels before downscaling. `0` turns downscaling off.

Old single-host configs (`"host": "vm"`) still load and are converted on the next `sshot machine` change.
After you edit the config by hand, run `sshot install` to restart the daemon.

## Updating and development

- `sshot upgrade` pulls the latest `master`, rebuilds, restarts the daemon and syncs every machine.
  It does nothing if the source hasn't changed; `--force` rebuilds anyway.
- From a checkout, `scripts/install-from-source.sh` builds and installs your working tree, then
  restarts the daemon and syncs all machines. Use it to try out changes before pushing.
- Bump `VERSION` when you change behaviour. Machines are compared on `VERSION` plus a hash of
  `vm/`, so edits to the remote scripts are pushed out even without a bump.

## Troubleshooting

- `sshot doctor` checks the config, SSH, the remote dir and version on each machine, and the daemon state.
- The daemon log is at `~/Library/Logs/sshot.log`.
- The daemon runs ssh non-interactively (`BatchMode`). If your key has a passphrase, store it in
  the agent or Keychain (`UseKeychain yes` + `AddKeysToAgent yes` in `~/.ssh/config`).
- sshot overrides `RemoteCommand` and `RequestTTY` from your `~/.ssh/config` (e.g. a tmux
  auto-attach) for its own connections; your interactive `ssh` is unaffected.
- Uninstall with `sshot machine remove <host>` for each machine (this deletes its screenshots too;
  `--keep-remote` leaves the machine alone), then `sshot uninstall` and delete `~/.local/bin/sshot`.
