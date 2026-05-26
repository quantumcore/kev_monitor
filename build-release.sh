#!/usr/bin/env bash
set -euo pipefail

export SOURCE_DATE_EPOCH=0

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$REPO_ROOT/dist"
mkdir -p "$OUTDIR"

# Safe Rust flags (no invalid -Cextra-filename, no fragile formatting)
RUSTFLAGS_COMMON="--remap-path-prefix ${HOME}=~ -Cmetadata=0"

# ────────────────────────────────────────────────
# Linux: x86_64-unknown-linux-musl
# ────────────────────────────────────────────────

build_linux() {
    echo "=== Building for x86_64-unknown-linux-musl ==="

    rustup target add x86_64-unknown-linux-musl 2>/dev/null

    if ! command -v musl-gcc &>/dev/null; then
        echo "Error: musl-gcc not found"
        echo "Install: sudo pacman -S musl || sudo apt install musl-tools"
        exit 1
    fi

    export CC=musl-gcc
    export AR=ar
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc
    export RUSTFLAGS="$RUSTFLAGS_COMMON"

    cargo build --release --target x86_64-unknown-linux-musl

    local src="$REPO_ROOT/target/x86_64-unknown-linux-musl/release/kev_monitor"
    local dst="$OUTDIR/kev_monitor-linux-x86_64"

    [[ -f "$src" ]] || { echo "Missing binary: $src"; exit 1; }

    strip "$src" || true
    cp "$src" "$dst"

    echo "  -> $dst"
    file "$dst"
    ldd "$dst" 2>&1 || true
}

# ────────────────────────────────────────────────
# Windows (ONLY works on Windows host)
# ────────────────────────────────────────────────

build_windows_msvc() {
    echo "=== Building for x86_64-pc-windows-msvc ==="

    rustup target add x86_64-pc-windows-msvc 2>/dev/null

    export RUSTFLAGS="$RUSTFLAGS_COMMON"

    cargo build --release --target x86_64-pc-windows-msvc

    local src="$REPO_ROOT/target/x86_64-pc-windows-msvc/release/kev_monitor.exe"
    local dst="$OUTDIR/kev_monitor-windows-x86_64.exe"

    [[ -f "$src" ]] || { echo "Missing binary: $src"; exit 1; }

    cp "$src" "$dst"
    echo "  -> $dst"
}

# ────────────────────────────────────────────────
# Windows GNU cross (Linux-friendly)
# ────────────────────────────────────────────────

build_windows_gnu() {
    echo "=== Building for x86_64-pc-windows-gnu ==="

    rustup target add x86_64-pc-windows-gnu 2>/dev/null

    if ! command -v x86_64-w64-mingw32-gcc &>/dev/null; then
        echo "Error: mingw-w64 not found"
        echo "Install: sudo pacman -S mingw-w64-gcc || sudo apt install gcc-mingw-w64-x86-64"
        exit 1
    fi

    export CC_x86_64_pc_windows_gnu=x86_64-w64-mingw32-gcc
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc
    export RUSTFLAGS="$RUSTFLAGS_COMMON"

    cargo build --release --target x86_64-pc-windows-gnu

    local src="$REPO_ROOT/target/x86_64-pc-windows-gnu/release/kev_monitor.exe"
    local dst="$OUTDIR/kev_monitor-windows-x86_64.exe"

    [[ -f "$src" ]] || { echo "Missing binary: $src"; exit 1; }

    cp "$src" "$dst"
    echo "  -> $dst"
}

# ────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────

case "${1:-all}" in
    linux)
        build_linux
        ;;

    windows)
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "MSVC build not supported on Linux. Use windows-gnu instead."
            exit 1
        fi
        build_windows_msvc
        ;;

    windows-gnu)
        build_windows_gnu
        ;;

    all)
        build_linux

        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            build_windows_gnu
        else
            build_windows_msvc
        fi
        ;;
    *)
        echo "Usage: $0 [linux|windows|windows-gnu|all]"
        exit 1
        ;;
esac

echo ""
echo "=== Done. Artifacts in $OUTDIR ==="
ls -lh "$OUTDIR"