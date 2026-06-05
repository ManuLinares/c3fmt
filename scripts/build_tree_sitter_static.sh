#!/usr/bin/env bash
# Build libtree-sitter.a from source for use in a fully static c3fmt binary.
#
# mirrors the tree-sitter/setup-action.
# The resulting archive lands at build/ts-lib/lib/libtree-sitter.a, which is the
# linker-search-paths directory used by the c3fmt-static project target.
#
# Usage (called automatically by the build-ts-lib prepare target):
#   c3c build build-ts-lib
#
# Requirements: cmake, cc, git

set -euo pipefail

TS_VERSION="${1:-0.26.9}"
TS_REPO="https://github.com/tree-sitter/tree-sitter"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
INSTALL_DIR="$PROJECT_DIR/build/ts-lib"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# dependency checks
for cmd in cmake git cc; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "error: '$cmd' not found in PATH" >&2
        exit 1
    fi
done

# skip rebuild if already built
if [[ -f "$INSTALL_DIR/lib/libtree-sitter.a" ]]; then
    echo "libtree-sitter.a already present at $INSTALL_DIR/lib — skipping build."
    echo "Delete $INSTALL_DIR to force a rebuild."
    exit 0
fi

echo "Cloning tree-sitter @ v${TS_VERSION} ..."
git clone "$TS_REPO" "$STAGING/tree-sitter" --quiet --filter=blob:none
git -C "$STAGING/tree-sitter" checkout "v${TS_VERSION}" --quiet

# from their github actions
if [[ -f "$STAGING/tree-sitter/CMakeLists.txt" ]]; then
    LIB_DIR="."
else
    LIB_DIR="lib"
fi

echo "Configuring (static) ..."
cmake -S "$STAGING/tree-sitter/$LIB_DIR" -B "$STAGING/build" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DCMAKE_INSTALL_LIBDIR=lib

echo "Building ..."
cmake --build "$STAGING/build" --parallel

echo "Installing to $INSTALL_DIR ..."
cmake --install "$STAGING/build"

echo "Done. Static library written to $INSTALL_DIR/lib/libtree-sitter.a"
