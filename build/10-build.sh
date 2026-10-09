#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Main Build Script
###############################################################################
# This script follows the @ublue-os/bluefin pattern for build scripts.
# It uses set -euo pipefail for strict error handling.
###############################################################################

# Enable nullglob for all glob operations to prevent failures on empty matches
shopt -s nullglob

echo "::group:: Overlay Brew Integration Files"

# Brew integration files from @ublue-os/brew OCI (tarball, systemd services, shell integration)
rsync -rvK /ctx/oci/brew/ /

echo "::endgroup::"

echo "::group:: Copy Custom Files"

# Copy Brewfiles to standard location
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/

# Consolidate Just Files
# Walk the tree and sort the inputs so a fork can organise recipes into
# subdirectories and the merged result is deterministic and idempotent. An
# unsorted concatenation makes the image layer differ between two builds of the
# same tree, so the build is not reproducible and a bisect cannot find a
# difference that is actually only a reordering.
mkdir -p /usr/share/ublue-os/just/
: >/usr/share/ublue-os/just/60-custom.just
mapfile -t recipes < <(find /ctx/custom/ujust -type f -iname '*.just' | LC_ALL=C sort)
for recipe in "${recipes[@]}"; do
	cat "${recipe}" >>/usr/share/ublue-os/just/60-custom.just
	printf '\n' >>/usr/share/ublue-os/just/60-custom.just
done

# Copy Flatpak preinstall files
mkdir -p /usr/share/flatpak/preinstall.d/
cp /ctx/custom/flatpaks/*.preinstall /usr/share/flatpak/preinstall.d/

echo "::endgroup::"

echo "::group:: Install Packages"

# Install the default packages and verify the DNF cache is working.
# gum is required by the default ujust recipes for interactive prompts.
dnf5 install -y tmux gum

### laptop-os system packages (Fedora repos)
# cups-pdf      - virtual PDF printer
# virt stack    - libvirt, qemu-kvm, virt-manager for VM workflows
dnf5 install -y cups-pdf libvirt qemu-kvm virt-manager

echo "::endgroup::"

echo "::group:: System Configuration"

# 1Password integration groups, with fixed GIDs chosen by us.
#
# 1Password authenticates the browser through the connecting process's effective
# group, and 1Password-BrowserSupport must be root:<onepassword> setgid. If the
# group does not exist, the RPM's `groupadd -r` creates it as a *system* group,
# which lands below GID_MIN (963 on a stock image). A sub-1000 GID is rejected
# with "invalid group attempted to connect", and on this image it additionally
# collides with the dynamic systemd users systemd-coredump (963) and pipewire
# (965) - users that `usermod` cannot move because nss-systemd synthesises them.
#
# Declaring the groups here, before any 1Password package is installed, means
# the package finds them already present and never allocates its own.
mkdir -p /usr/lib/sysusers.d
cat >/usr/lib/sysusers.d/1password.conf <<'EOF'
# 1Password browser integration. GIDs are pinned: see build/10-build.sh.
g onepassword 1500 -
g onepassword-cli 1501 -
EOF

# 1Password-BrowserSupport refuses to start when ptrace_scope is 0: it logs
# "Yama is absent or ptrace_scope is set to 0" and aborts, because its own
# anti-tampering checks depend on Yama restricting who may inspect it. Bluefin
# ships 0. This is also the safer default, so set it in the image rather than
# at runtime.
cat >/usr/lib/sysctl.d/90-1password.conf <<'EOF'
# Required by 1Password-BrowserSupport (op-startup/src/linux.rs).
kernel.yama.ptrace_scope = 1
EOF

# Enable/disable systemd services
systemctl enable podman.socket
systemctl enable brew-setup.service
systemctl enable brew-update.timer
systemctl enable brew-upgrade.timer
systemctl enable libvirtd.socket libvirtd.service
# Example: systemctl mask unwanted-service

echo "::endgroup::"

# Restore default glob behavior
shopt -u nullglob

echo "Custom build complete!"
