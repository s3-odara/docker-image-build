#!/bin/bash -x

USERNAME="user"
USER_COMMENT="General User"
USER_PASSWORD="user"
SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICblPjqCTllD9zDPGS++Urlw4XqyXixufgn8iFEoDnkK"

if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/zsh -G wheel -c "$USER_COMMENT" "$USERNAME"
    echo "User $USERNAME created."
else
    echo "User $USERNAME already exists."
fi

echo "$USERNAME:$USER_PASSWORD" | chpasswd

SSH_DIR="/home/$USERNAME/.ssh"
mkdir -p "$SSH_DIR"
echo "$SSH_KEY" > "$SSH_DIR/authorized_keys"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/authorized_keys"
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"

ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/#ja_JP.UTF-8/ja_JP.UTF-8/' /etc/locale.gen

locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf

sed -i \
    -e 's/CFLAGS="-march=x86-64/CFLAGS="-march=x86-64-v3/' \
    -e '/^LDFLAGS=/ s/"$/ -fuse-ld=mold"/' \
    -e '/^LTOFLAGS=/a RUSTFLAGS="-C opt-level=3 -C link-arg=-fuse-ld=mold -C target-cpu=x86-64-v3"' \
    -e "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$(nproc)\"/" \
    /etc/makepkg.conf


# pacman
sed -i \
    -e 's/^#Color/Color/' \
    -e 's/^ParallelDownloads = 5/ParallelDownloads = 10/' \
    /etc/pacman.conf

curl -s "https://archlinux.org/mirrorlist/?country=JP&protocol=https" | \
    sed -e 's/^#Server/Server/' -e '/^#/d' | rankmirrors -v - > /etc/pacman.d/mirrorlist

useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder

su - builder -c "git clone https://aur.archlinux.org/paru-bin.git"
su - builder -c "cd paru-bin && makepkg -si --noconfirm"

PACKAGES="doasedit-alternative zsh-pure-prompt"
sudo -u builder bash -c "paru -S --noconfirm --needed $PACKAGES"

sudo -u builder bash -c "yes | paru -Scc"

userdel -r builder

sed -i \
    -e 's/CFLAGS="-march=x86-64-v3/CFLAGS="-march=native/' \
    -e 's/RUSTFLAGS="-C opt-level=3 -C link-arg=-fuse-ld=mold -C target-cpu=x86-64-v3"/RUSTFLAGS="-C opt-level=3 -C link-arg=-fuse-ld=mold -C target-cpu=native"/' \
    -e "s/#MAKEFLAGS=\"-j$(nproc)\"/MAKEFLAGS=\"-j16\"/" \
    -e '/^BUILDENV=/ s/!ccache/ccache/' \
    /etc/makepkg.conf

cat <<EOF > /etc/doas.conf
permit nopass :wheel
EOF

chown root:root /etc/doas.conf
chmod 0600 /etc/doas.conf

ln -sf /usr/bin/doas /usr/local/bin/sudo
rm /etc/sudoers.d/builder


sudo -u "$USERNAME" bash <<EOF
    set -x

    mkdir -p "/home/$USERNAME/git"

    TARGET_DIR="/home/$USERNAME/git/dotfiles"
    REPO_URL="https://github.com/s3-odara/dotfiles.git"

    git clone "\$REPO_URL" "\$TARGET_DIR"

    echo "Running make stow..."
    cd "\$TARGET_DIR"
    make stow
    cd home
    find .ssh .gnupg -type d -exec chmod 700 {} +
    find .ssh .gnupg -type f -exec chmod 600 {} +
    gpg --locate-keys haruta@s3-odara.net

    vim -u "/home/$USERNAME/.vimrc" -i NONE -n -N -S "/home/$USERNAME/.vim/update_minpac.vim"
EOF

echo StreamLocalBindUnlink yes | sudo tee /etc/ssh/sshd_config.d/StreamLocalBindUnlink.conf > /dev/null
systemctl enable sshd

echo "Setup complete."
