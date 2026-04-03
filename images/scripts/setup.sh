#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

USERNAME="${USERNAME:-user}"
USER_COMMENT="${USER_COMMENT:-General User}"
USER_PASSWORD="${USER_PASSWORD:-}"
SSH_KEY="${SSH_KEY:-}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/s3-odara/dotfiles.git}"
ENVFILE_REPO="${ENVFILE_REPO:-https://github.com/s3-odara/envfile.git}"
MAKEFLAGS_TARGET="${MAKEFLAGS_TARGET:-16}"

log() {
    echo "[setup] $*"
}

write_known_hosts() {
    local ssh_dir="$1"
    install -d -m 700 "$ssh_dir"
    install -m 600 /dev/null "$ssh_dir/known_hosts"
    cat <<'EOF' > "$ssh_dir/known_hosts"
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
gitlab.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf
EOF
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
write_known_hosts "$SSH_DIR"
if [ -n "$SSH_KEY" ]; then
    mkdir -p "$SSH_DIR"
    echo "$SSH_KEY" > "$SSH_DIR/authorized_keys"
    chmod 700 "$SSH_DIR"
    chmod 600 "$SSH_DIR/authorized_keys"
    chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
else
    log "No SSH_KEY provided; skipping authorized_keys."
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

mkdir -p /etc/systemd/journald.conf.d
cat <<'EOF' > /etc/systemd/journald.conf.d/00-volatile.conf
[Journal]
Storage=volatile
RuntimeMaxUse=64M
EOF
rm -rf /var/log/journal

# sockets setup
cat <<EOF > /etc/tmpfiles.d/gui-sockets.conf
d  /run/user/1000        0700 1000 1000 -
d  /run/user/1000/pulse  0700 1000 1000 -
L+ /run/user/1000/wayland-1    - - - - /mnt/.container_sockets/wayland-1
L+ /run/user/1000/pulse/native - - - - /mnt/.container_sockets/pulse-native
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
if [ -d /var/cache/pacman/pkg ]; then
    find /var/cache/pacman/pkg -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi
if [ -d /var/lib/pacman/sync ]; then
    find /var/lib/pacman/sync -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

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

    export HOME="$USER_HOME"
    export GNUPGHOME="$USER_HOME/.gnupg"
    install -d -m 700 "\$GNUPGHOME"

    mkdir -p "$USER_HOME/git"

    TARGET_DIR="$USER_HOME/git/dotfiles"
    REPO_URL="$DOTFILES_REPO"
    ENVFILE_DIR="$USER_HOME/git/envfile"
    ENVFILE_REPO_URL="$ENVFILE_REPO"

    if [ ! -d "\$TARGET_DIR/.git" ]; then
        GIT_TERMINAL_PROMPT=0 git clone --depth 1 "\$REPO_URL" "\$TARGET_DIR"
    fi

    if [ ! -d "\$ENVFILE_DIR/.git" ]; then
        GIT_TERMINAL_PROMPT=0 git clone --depth 1 "\$ENVFILE_REPO_URL" "\$ENVFILE_DIR"
    fi

    echo "Running make stow..."
    cd "\$TARGET_DIR"
    make bootstrap stow-arch

    install -d -m 700 "$USER_HOME/.config/secrets"

    cd home
    if command -v gpg >/dev/null 2>&1; then
        gpg --homedir "\$GNUPGHOME" --locate-keys haruta@s3-odara.net || true
        if gpg --homedir "\$GNUPGHOME" --list-keys haruta@s3-odara.net >/dev/null 2>&1; then
            fingerprint=\$(gpg --homedir "\$GNUPGHOME" --with-colons --fingerprint haruta@s3-odara.net | awk -F: '/^fpr:/ {print \$10; exit}')
            if [ -n "\$fingerprint" ]; then
                printf '%s:6:\n' "\$fingerprint" | gpg --homedir "\$GNUPGHOME" --import-ownertrust
            fi
        fi
    fi

    if command -v vim >/dev/null 2>&1 && [ -f "$USER_HOME/.vim/update_minpac.vim" ]; then
        vim -u "$USER_HOME/.vimrc" -i NONE -n -N -S "$USER_HOME/.vim/update_minpac.vim"
    fi
EOF
fi

SSH_DIR="/home/$USERNAME/.ssh"
write_known_hosts "$SSH_DIR"

if [ -n "$SSH_KEY" ]; then
    install -m 600 /dev/null "$SSH_DIR/authorized_keys"
    echo "$SSH_KEY" > "$SSH_DIR/authorized_keys"
else
    log "No SSH_KEY provided; skipping authorized_keys."
fi
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"


mkdir -p /etc/ssh/sshd_config.d
echo StreamLocalBindUnlink yes > /etc/ssh/sshd_config.d/StreamLocalBindUnlink.conf
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable sshd || true
fi

if [ -x /usr/local/bin/prune-manpages ]; then
    /usr/local/bin/prune-manpages
fi

log "Setup complete."
