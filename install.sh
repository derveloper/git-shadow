#!/usr/bin/env bash
set -euo pipefail

REPO="https://raw.githubusercontent.com/derveloper/git-shadow/main/git-shadow"
INSTALL_DIR="${GIT_SHADOW_INSTALL_DIR:-$HOME/.local/bin}"
BINARY="git-shadow"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$@"; }
ok()    { printf '\033[1;32m==>\033[0m %s\n' "$@"; }
fail()  { printf '\033[1;31m==>\033[0m %s\n' "$@" >&2; exit 1; }

# download
info "downloading git-shadow..."
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if command -v curl &>/dev/null; then
    curl -fsSL "$REPO" -o "$tmp"
elif command -v wget &>/dev/null; then
    wget -qO "$tmp" "$REPO"
else
    fail "need curl or wget"
fi

grep -q "git-shadow" "$tmp" || fail "download failed or file corrupted"

# install
mkdir -p "$INSTALL_DIR"
mv "$tmp" "${INSTALL_DIR}/${BINARY}"
chmod +x "${INSTALL_DIR}/${BINARY}"
trap - EXIT

ok "installed to ${INSTALL_DIR}/${BINARY}"

# check PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
    echo ""
    info "$INSTALL_DIR is not in PATH. add to your shell rc:"
    echo ""
    echo "    export PATH=\"${INSTALL_DIR}:\$PATH\""
    echo ""
fi

# shell integration
echo ""
info "optional: transparent git init wrapping (add to .zshrc/.bashrc):"
echo ""
echo "    eval \"\$(git shadow shell-init)\""
echo ""

ok "done. try: git shadow --help"
