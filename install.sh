#!/bin/sh
# Install or update sshot on macOS.
#   curl -fsSL https://raw.githubusercontent.com/korih/screenshot-ssh/master/install.sh | sh
# By default this downloads the latest release binary. Set SSHOT_REF (branch or tag) or
# SSHOT_FROM_SOURCE=1 to build from source instead (needs the Xcode Command Line Tools).
# Env: SSHOT_BIN_DIR (default ~/.local/bin), SSHOT_FORCE=1 (reinstall even if up to date),
#      SSHOT_REPO and SSHOT_SRC (source builds: repo URL and checkout dir).
set -eu

github="https://github.com/korih/screenshot-ssh"
dest="${SSHOT_BIN_DIR:-$HOME/.local/bin}"
plist="$HOME/Library/LaunchAgents/com.sshot.daemon.plist"

die() { echo "sshot: $*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "this installer is for macOS; remote machines are set up with 'sshot machine add'"

# If the running daemon uses the binary we just installed, restart it and bring every machine
# to the new version.
restart_daemon() {
  daemon_bin="$(plutil -extract ProgramArguments.0 raw "$plist" 2>/dev/null || true)"
  # Same file (device:inode); POSIX sh has no -ef.
  if [ -n "$daemon_bin" ] && [ "$(stat -L -f %d:%i "$daemon_bin" 2>/dev/null)" = "$(stat -L -f %d:%i "$dest/sshot")" ]; then
    "$dest/sshot" install >/dev/null
    "$dest/sshot" machine sync || true
    echo "If Cmd+V stops working, re-allow sshot in System Settings > Privacy & Security > Accessibility."
  else
    echo "Next: sshot machine add <ssh-host>   (e.g. user@10.0.0.5 or an alias from ~/.ssh/config)"
  fi
}

install_from_source() {
  repo="${SSHOT_REPO:-$github.git}"
  ref="${SSHOT_REF:-master}"
  src="${SSHOT_SRC:-$HOME/.local/share/sshot/src}"
  if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
    die "building from source needs the Xcode Command Line Tools. Run 'xcode-select --install', then run this again."
  fi

  if [ -d "$src/.git" ]; then
    before="$(git -C "$src" rev-parse HEAD)"
    git -C "$src" remote set-url origin "$repo"
    git -C "$src" fetch -q --depth 1 origin "$ref"
    git -C "$src" checkout -q --force FETCH_HEAD
  else
    before=""
    mkdir -p "$(dirname "$src")"
    rm -rf "$src"
    git clone -q --depth 1 --branch "$ref" "$repo" "$src"
  fi
  after="$(git -C "$src" rev-parse HEAD)"

  if [ "$before" = "$after" ] && [ -x "$dest/sshot" ] && [ -z "${SSHOT_FORCE:-}" ]; then
    echo "sshot is up to date ($("$dest/sshot" version), ${after%"${after#???????}"})"
    exit 0
  fi

  echo "building sshot from $repo ($ref, ${after%"${after#???????}"})"
  SSHOT_BIN_DIR="$dest" "$src/scripts/install-from-source.sh"
}

install_release() {
  # /releases/latest redirects to /releases/tag/<tag>.
  latest="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$github/releases/latest")" ||
    die "could not reach $github"
  tag="${latest##*/}"
  case "$tag" in
    v*) ;;
    *) die "no release found at $github/releases; set SSHOT_FROM_SOURCE=1 to build from source" ;;
  esac

  if [ -x "$dest/sshot" ] && [ -z "${SSHOT_FORCE:-}" ]; then
    current="$("$dest/sshot" version 2>/dev/null || true)"
    case "$current" in
      "sshot ${tag#v}+"*) echo "sshot is up to date (${current#sshot })"; exit 0 ;;
    esac
  fi

  echo "downloading sshot $tag"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  for f in sshot-macos.tar.gz sshot-macos.tar.gz.sha256; do
    curl -fsSL -o "$tmp/$f" "$github/releases/download/$tag/$f" || die "could not download $f for $tag"
  done
  (cd "$tmp" && shasum -a 256 -c sshot-macos.tar.gz.sha256 >/dev/null) || die "checksum mismatch for $tag"
  tar -xzf "$tmp/sshot-macos.tar.gz" -C "$tmp"

  mkdir -p "$dest"
  install -m 755 "$tmp/sshot" "$dest/sshot"
  echo "installed $dest/sshot ($("$dest/sshot" version))"
  restart_daemon
}

if [ -n "${SSHOT_REF:-}" ] || [ -n "${SSHOT_FROM_SOURCE:-}" ]; then
  install_from_source
else
  install_release
fi

case ":$PATH:" in
  *":$dest:"*) ;;
  *) echo "Note: add $dest to your PATH." ;;
esac
