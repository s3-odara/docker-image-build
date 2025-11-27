#!/bin/bash
set -e

pacman-key --init
pacman-key --populate archlinux

curl -s "https://archlinux.org/mirrorlist/?protocol=https&use_mirror_status=on" | \
        sed -e 's/^#Server/Server/' -e '/^#/d' | \
            head -n 50 > /etc/pacman.d/mirrorlist

pacman -Syu --noconfirm

PACKAGES=(
    base-devel
    vi
    tmux
    gnupg
    zsh
    zsh-syntax-highlighting
    zsh-autosuggestions
    git
    vim
    wget
    curl
    man-db
    doas
    mold
    clang
    ccache
    cloud-init
    zsh-completions
)
pacman -S --noconfirm --needed "${PACKAGES[@]}"

sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/#ja_JP.UTF-8/ja_JP.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime

useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder

su - builder -c "git clone https://aur.archlinux.org/paru-bin.git"
su - builder -c "cd paru-bin && makepkg -si --noconfirm"

PACKAGES=(
    doasedit-alternative
)
paru -S --noconfirm --needed "${PACKAGES[@]}"

ln -s /usr/bin/doas /usr/local/bin/sudo
echo "permit persist user" > /etc/doas.conf


userdel -r builder
rm /etc/sudoers.d/builder

systemctl enable sshd
systemctl enable cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service

sed -i \
    -e 's/CFLAGS="-march=x86-64/CFLAGS="-march=native/' \
    -e '/^LDFLAGS=/ s/"$/ -fuse-ld=mold"/' \
    -e '/^LTOFLAGS=/a RUSTFLAGS="-C opt-level=3 -C link-arg=-fuse-ld=mold -C target-cpu=native"' \
    -e 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j16"/' \
    -e '/^BUILDENV=/ s/!ccache/ccache/' \
    "/etc/makepkg.conf"


paru -Scc --noconfirm
rm -rf /var/cache/pacman/pkg/*
rm -rf /usr/share/doc/*
