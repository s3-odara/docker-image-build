#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

USERNAME="${USERNAME:-user}"
USER_COMMENT="${USER_COMMENT:-General User}"
USER_PASSWORD="${USER_PASSWORD:-}"
SSH_KEY="${SSH_KEY:-}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/s3-odara/dotfiles.git}"
MAKEFLAGS_TARGET="${MAKEFLAGS_TARGET:-16}"

log() {
    echo "[setup] $*"
}

if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/zsh -G wheel -c "$USER_COMMENT" "$USERNAME"
    log "User $USERNAME created."
else
    log "User $USERNAME already exists."
fi

if [ -n "$USER_PASSWORD" ]; then
    echo "$USERNAME:$USER_PASSWORD" | chpasswd
else
    passwd -l "$USERNAME" || true
    log "No USER_PASSWORD provided; account locked."
fi

SSH_DIR="/home/$USERNAME/.ssh"
if [ -n "$SSH_KEY" ]; then
    mkdir -p "$SSH_DIR"
    echo "$SSH_KEY" > "$SSH_DIR/authorized_keys"
    chmod 700 "$SSH_DIR"
    chmod 600 "$SSH_DIR/authorized_keys"
    chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
else
    log "No SSH_KEY provided; skipping authorized_keys."
fi

if [ -e /run/systemd/resolve/stub-resolv.conf ]; then
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

if [ -e /usr/share/zoneinfo/Asia/Tokyo ]; then
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
fi

sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#ja_JP.UTF-8/ja_JP.UTF-8/' /etc/locale.gen

locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf

NPROC="$(nproc)"
sed -i \
    -e 's/CFLAGS="-march=x86-64/CFLAGS="-march=x86-64-v3/' \
    -e '/^LDFLAGS=/ s/"$/ -fuse-ld=mold"/' \
    -e '/^LTOFLAGS=/a RUSTFLAGS="-C opt-level=3 -C link-arg=-fuse-ld=mold -C target-cpu=x86-64-v3"' \
    -e "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$NPROC\"/" \
    /etc/makepkg.conf


# pacman
sed -i \
    -e 's/^#Color/Color/' \
    -e 's/^ParallelDownloads = 5/ParallelDownloads = 10/' \
    /etc/pacman.conf

MIRRORLIST_URL="https://archlinux.org/mirrorlist/?country=JP&protocol=https"
if command -v rankmirrors >/dev/null 2>&1; then
    curl -fsSL --retry 5 --retry-delay 2 "$MIRRORLIST_URL" | \
        sed -e 's/^#Server/Server/' -e '/^#/d' | \
        rankmirrors -v - > /etc/pacman.d/mirrorlist
else
    curl -fsSL --retry 5 --retry-delay 2 "$MIRRORLIST_URL" | \
        sed -e 's/^#Server/Server/' -e '/^#/d' > /etc/pacman.d/mirrorlist
fi

cat <<EOF > /etc/doas.conf
permit nopass :wheel
EOF

chown root:root /etc/doas.conf
chmod 0600 /etc/doas.conf

if [ -x /usr/bin/doas ]; then
    ln -sf /usr/bin/doas /usr/local/bin/sudo
fi

if grep -qE '^#?PACMAN_AUTH=' /etc/makepkg.conf; then
    sed -i 's/^#\?PACMAN_AUTH=.*/PACMAN_AUTH=(\/usr\/bin\/doas)/' /etc/makepkg.conf
else
    echo 'PACMAN_AUTH=(/usr/bin/doas)' >> /etc/makepkg.conf
fi

useradd -m -s /bin/bash -G wheel builder

su - builder -c "rm -rf ~/yay-bin"
su - builder -c "GIT_TERMINAL_PROMPT=0 git clone --depth 1 https://aur.archlinux.org/yay-bin.git ~/yay-bin"
su - builder -c "cd ~/yay-bin && makepkg -si --noconfirm --needed"

PACKAGES="doasedit-alternative zsh-pure-prompt"
su - builder -c "yay -S --noconfirm --needed $PACKAGES"

su - builder -c "yes | yay -Scc" || true

# Work around pacman cache cleanup failures when download directories exist.

userdel -r builder

sed -i \
    -e 's/CFLAGS="-march=x86-64-v3/CFLAGS="-march=native/' \
    -e 's/RUSTFLAGS="-C opt-level=3 -C link-arg=-fuse-ld=mold -C target-cpu=x86-64-v3"/RUSTFLAGS="-C opt-level=3 -C link-arg=-fuse-ld=mold -C target-cpu=native"/' \
    -e "s/^MAKEFLAGS=.*/MAKEFLAGS=\"-j$MAKEFLAGS_TARGET\"/" \
    -e '/^BUILDENV=/ s/!ccache/ccache/' \
    /etc/makepkg.conf

USER_HOME="/home/$USERNAME"
if [ -d "$USER_HOME" ]; then
    su - "$USERNAME" -s /bin/bash <<EOF
    set -euo pipefail

    mkdir -p "$USER_HOME/git"

    TARGET_DIR="$USER_HOME/git/dotfiles"
    REPO_URL="$DOTFILES_REPO"

    if [ ! -d "\$TARGET_DIR/.git" ]; then
        GIT_TERMINAL_PROMPT=0 git clone --depth 1 "\$REPO_URL" "\$TARGET_DIR"
    fi

    echo "Running make stow..."
    cd "\$TARGET_DIR"
    make bootstrap stow-arch
    cd home
    if command -v gpg >/dev/null 2>&1; then
        gpg --locate-keys haruta@s3-odara.net || true
    fi

    if command -v vim >/dev/null 2>&1 && [ -f "$USER_HOME/.vim/update_minpac.vim" ]; then
        vim -u "$USER_HOME/.vimrc" -i NONE -n -N -S "$USER_HOME/.vim/update_minpac.vim"
    fi
EOF
fi

mkdir -p /etc/ssh/sshd_config.d
echo StreamLocalBindUnlink yes > /etc/ssh/sshd_config.d/StreamLocalBindUnlink.conf
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable sshd || true
fi

log "Setup complete."
