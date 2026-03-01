#!/usr/bin/env bash
# Builds sshpass from source and copies the binary into the app Resources
# so the app can use it without requiring the user to install sshpass.
# Run from repo root: ./scripts/build-sshpass.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCES="$REPO_ROOT/Sources/AxeSSH/Resources"
BUILD_DIR="$REPO_ROOT/.build/sshpass-src"
VERSION="1.09"
TARBALL="sshpass-${VERSION}.tar.gz"
URL="https://sourceforge.net/projects/sshpass/files/sshpass/${VERSION}/${TARBALL}/download"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [[ ! -f "$TARBALL" ]]; then
  echo "Downloading sshpass ${VERSION}..."
  curl -L -o "$TARBALL" "$URL"
fi

echo "Extracting..."
tar -xzf "$TARBALL"
cd "sshpass-${VERSION}"

echo "Configuring..."
./configure --prefix="$BUILD_DIR/install" --disable-dependency-tracking

echo "Building..."
make
make install

mkdir -p "$RESOURCES"
cp -f "$BUILD_DIR/install/bin/sshpass" "$RESOURCES/sshpass"
chmod +x "$RESOURCES/sshpass"

echo "Done. sshpass binary is at $RESOURCES/sshpass"
