#!/bin/bash
set -eux -o pipefail

USERNAME="${USERNAME:-robot}"

echo -e "\e[1;32mInstalling pixi and Rust (official installers)\e[0m"

# Install for the configured robot user. Both installers target $HOME.
export HOME="/home/$USERNAME"

# pixi - package/environment manager
if [ ! -x "$HOME/.pixi/bin/pixi" ]; then
    curl -fsSL https://pixi.sh/install.sh | bash
fi
ln -sf "$HOME/.pixi/bin/pixi" /usr/local/bin/pixi

# Rust via rustup (not the apt rustc/cargo, which can be outdated)
if [ ! -x "$HOME/.cargo/bin/rustc" ]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
fi

# Ensure the toolchains are usable via the default PATH for the user
cat >> "$HOME/.bashrc" <<'EOF'

# pixi
export PATH="$HOME/.pixi/bin:$PATH"
# Rust (rustup)
export PATH="$HOME/.cargo/bin:$PATH"
EOF

chown -R "$USERNAME:$USERNAME" "$HOME/.pixi" "$HOME/.cargo" 2>/dev/null || true