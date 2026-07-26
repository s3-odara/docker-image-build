#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

USERNAME="${USERNAME:-user}"
USER_COMMENT="${USER_COMMENT:-General User}"
USER_PASSWORD="${USER_PASSWORD:-}"
SSH_KEY="${SSH_KEY:-}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/s3-odara/dotfiles.git}"
ENVFILE_REPO="${ENVFILE_REPO:-https://github.com/s3-odara/envfile.git}"
PARU_OVERLAY_REPO="${PARU_OVERLAY_REPO:-https://github.com/s3-odara/paru-overlay}"
MAKEFLAGS_TARGET="${MAKEFLAGS_TARGET:-16}"
ARCH="$(uname -m)"

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

if [ -e /usr/share/zoneinfo/Asia/Tokyo ]; then
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
fi

sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#ja_JP.UTF-8/ja_JP.UTF-8/' /etc/locale.gen

locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf

NPROC="$(nproc)"
if [ "$ARCH" = "x86_64" ]; then
    sed -i \
        -e 's/CFLAGS="-march=x86-64/CFLAGS="-march=x86-64-v3/' \
        -e '/^LDFLAGS=/ s/"$/ -fuse-ld=mold"/' \
        -e '/^LTOFLAGS=/a RUSTFLAGS="-C opt-level=3 -C link-arg=-fuse-ld=mold -C target-cpu=x86-64-v3"' \
        -e "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$NPROC\"/" \
        /etc/makepkg.conf
else
    sed -i \
        -e "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$NPROC\"/" \
        /etc/makepkg.conf
fi


# pacman
sed -i \
    -e 's/^#Color/Color/' \
    -e 's/^ParallelDownloads = 5/ParallelDownloads = 10/' \
    /etc/pacman.conf

if [ "$ARCH" = "aarch64" ]; then
    echo 'Server = http://nj.us.mirror.archlinuxarm.org/$arch/$repo' > /etc/pacman.d/mirrorlist
else
    MIRRORLIST_URL="https://archlinux.org/mirrorlist/?country=JP&protocol=https"
    if command -v rankmirrors >/dev/null 2>&1; then
        curl -fsSL --retry 5 --retry-delay 2 "$MIRRORLIST_URL" | \
            sed -e 's/^#Server/Server/' -e '/^#/d' | \
            rankmirrors -v - > /etc/pacman.d/mirrorlist
    else
        curl -fsSL --retry 5 --retry-delay 2 "$MIRRORLIST_URL" | \
            sed -e 's/^#Server/Server/' -e '/^#/d' > /etc/pacman.d/mirrorlist
    fi
fi

install -m 600 -o root -g root /dev/null /etc/doas.conf
cat <<EOF > /etc/doas.conf
permit nopass :wheel
EOF

install -d -m 755 /etc/systemd/journald.conf.d
install -m 644 -o root -g root /dev/null /etc/systemd/journald.conf.d/00-volatile.conf
cat <<'EOF' > /etc/systemd/journald.conf.d/00-volatile.conf
[Journal]
Storage=volatile
RuntimeMaxUse=64M
EOF
rm -rf /var/log/journal

# sockets setup
install -d -m 755 /etc/tmpfiles.d
install -m 644 -o root -g root /dev/null /etc/tmpfiles.d/gui-sockets.conf
cat <<EOF > /etc/tmpfiles.d/gui-sockets.conf
d  /run/user/1000        0700 1000 1000 -
d  /run/user/1000/pulse  0700 1000 1000 -
d  /tmp/.X11-unix        1777 root root -
L+ /run/user/1000/wayland-1    - - - - /mnt/.container_sockets/wayland-1
L+ /run/user/1000/pulse/native - - - - /mnt/.container_sockets/pulse-native
EOF

if [ -x /usr/bin/doas ]; then
    ln -sf /usr/bin/doas /usr/local/bin/sudo
fi

if grep -qE '^#?PACMAN_AUTH=' /etc/makepkg.conf; then
    sed -i 's/^#\?PACMAN_AUTH=.*/PACMAN_AUTH=(\/usr\/bin\/doas)/' /etc/makepkg.conf
else
    echo 'PACMAN_AUTH=(/usr/bin/doas)' >> /etc/makepkg.conf
fi

useradd -m -s /bin/bash -G wheel builder

su - builder -c "rm -rf ~/git/paru-overlay"
su - builder -c "mkdir -p ~/git"
su - builder -c "GIT_TERMINAL_PROMPT=0 git clone --depth 1 '$PARU_OVERLAY_REPO' ~/git/paru-overlay"
su - builder -c "cd ~/git/paru-overlay/packages/paru && makepkg -sri --noconfirm --needed"

install -d -m 700 -o builder -g builder /home/builder/.config/paru
install -m 600 -o builder -g builder /dev/null /home/builder/.config/paru/paru.conf
cat <<EOF > /home/builder/.config/paru/paru.conf
Include = /etc/paru.conf

[options]
Mode = rp

[paru-overlay]
Path = /home/builder/git/paru-overlay/packages
Url = $PARU_OVERLAY_REPO
Depth = 3
GenerateSrcinfo = true
EOF

PACKAGES="doasedit-alternative zsh-pure-prompt"
su - builder -c "paru -Sy --pkgbuilds --noconfirm"
su - builder -c "paru -S --noconfirm --needed $PACKAGES"

su - builder -c "yes | paru -Scc" || true

# Work around pacman cache cleanup failures when download directories exist.
if [ -d /var/cache/pacman/pkg ]; then
    find /var/cache/pacman/pkg -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi
if [ -d /var/lib/pacman/sync ]; then
    find /var/lib/pacman/sync -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

userdel -r builder

if [ "$ARCH" = "x86_64" ]; then
    sed -i \
        -e 's/CFLAGS="-march=x86-64-v3/CFLAGS="-march=native/' \
        -e 's/RUSTFLAGS="-C opt-level=3 -C link-arg=-fuse-ld=mold -C target-cpu=x86-64-v3"/RUSTFLAGS="-C opt-level=3 -C link-arg=-fuse-ld=mold -C target-cpu=native"/' \
        -e "s/^MAKEFLAGS=.*/MAKEFLAGS=\"-j$MAKEFLAGS_TARGET\"/" \
        -e '/^BUILDENV=/ s/!ccache/ccache/' \
        /etc/makepkg.conf
else
    sed -i \
        -e "s/^MAKEFLAGS=.*/MAKEFLAGS=\"-j$MAKEFLAGS_TARGET\"/" \
        -e '/^BUILDENV=/ s/!ccache/ccache/' \
        /etc/makepkg.conf
fi

USER_HOME="/home/$USERNAME"
if [ -d "$USER_HOME" ]; then
    su - "$USERNAME" -s /bin/bash <<EOF
    set -euo pipefail

    export HOME="$USER_HOME"
    export GNUPGHOME="$USER_HOME/.gnupg"
    export SSH_DIR="$USER_HOME/.ssh"
    install -d -m 700 "\$GNUPGHOME"
    install -d -m 700 "\$SSH_DIR"

    mkdir -p "$USER_HOME/git"

    git_clone_once() {
        local dir="\$1"
        local url="\$2"

        if [ ! -d "\$dir/.git" ]; then
            GIT_TERMINAL_PROMPT=0 git clone --depth 1 "\$url" "\$dir"
        fi
    }

    TARGET_DIR="$USER_HOME/git/dotfiles"
    REPO_URL="$DOTFILES_REPO"
    ENVFILE_DIR="$USER_HOME/git/envfile"
    ENVFILE_REPO_URL="$ENVFILE_REPO"

    git_clone_once "\$TARGET_DIR" "\$REPO_URL"
    git_clone_once "\$ENVFILE_DIR" "\$ENVFILE_REPO_URL"

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
chmod 700 "$SSH_DIR"


install -d -m 755 /etc/ssh/sshd_config.d
install -m 644 -o root -g root /dev/null /etc/ssh/sshd_config.d/StreamLocalBindUnlink.conf
echo StreamLocalBindUnlink yes > /etc/ssh/sshd_config.d/StreamLocalBindUnlink.conf
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable sshd || true
fi

if [ -x /usr/local/bin/prune-manpages ]; then
    /usr/local/bin/prune-manpages
fi

log "Setup complete."
