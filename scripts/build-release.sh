#!/usr/bin/env bash
# Build a universal (arm64 + x86_64) sshot binary and package it for a release.
# Outputs dist/sshot, dist/sshot-macos.tar.gz and dist/sshot-macos.tar.gz.sha256.
# Each arch is built on its own and joined with lipo, because a multi-arch `swift build`
# can't resolve the EmbedPayload build-tool plugin.
set -euo pipefail

cd "$(dirname "$0")/.."
dist=dist
rm -rf "$dist"
mkdir -p "$dist"

bins=()
for arch in arm64 x86_64; do
  swift build -c release --arch "$arch"
  bins+=("$(swift build -c release --arch "$arch" --show-bin-path)/sshot")
done

lipo -create -output "$dist/sshot" "${bins[@]}"
codesign --force --sign - "$dist/sshot"
lipo -info "$dist/sshot"
"$dist/sshot" version

tar -C "$dist" -czf "$dist/sshot-macos.tar.gz" sshot
(cd "$dist" && shasum -a 256 sshot-macos.tar.gz > sshot-macos.tar.gz.sha256)
cat "$dist/sshot-macos.tar.gz.sha256"
