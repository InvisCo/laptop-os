#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Main Build Script
###############################################################################
# This script follows the @ublue-os/bluefin pattern for build scripts.
# It uses set -euo pipefail for strict error handling.
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

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

# laptop-os dock defaults over Bluefin's dash-to-dock (favorite-apps only)
cp /ctx/overrides/dconf/zz1-laptop-os.gschema.override /usr/share/glib-2.0/schemas/
glib-compile-schemas /usr/share/glib-2.0/schemas

echo "::endgroup::"

echo "::group:: Install Packages"

# Install the default packages and verify the DNF cache is working.
# gum is required by the default ujust recipes for interactive prompts.
dnf5 install -y tmux gum

### laptop-os system packages (Fedora repos)
# cups-pdf      - virtual PDF printer
# virt stack    - libvirt, qemu-kvm, virt-manager for VM workflows
dnf5 install -y cups-pdf libvirt qemu-kvm virt-manager

### Zed editor via COPR (not packaged in Fedora repos)
# cjatherton/zed tracks upstream releases and builds for fedora-44.
copr_install_isolated "cjatherton/zed" zed

echo "::endgroup::"

echo "::group:: System Configuration"

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
