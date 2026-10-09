#!/usr/bin/env bash

# Exit on error, unset variable, or pipe failure
set -euo pipefail

###############################################################################
# COSMIC desktop (System76), replacing GNOME on this image.
# Fedora 44 ships COSMIC in the official repos, so no COPR is needed.
# cosmic-session requires cosmic-greeter and xdg-desktop-portal-cosmic, and
# cosmic-greeter in turn requires greetd. GNOME's shell/session/greeter are
# removed so cosmic-greeter is the only display manager.
###############################################################################

echo "::group:: Remove GNOME desktop"

# gnome-shell removal cascades mutter, gnome-session*, gnome-classic-session,
# gnome-settings-daemon and xdg-desktop-portal-gnome. gdm removal cascades
# gnome-initial-setup. These have no other dependents and must go explicitly:
#   gnome-tour gnome-user-docs gnome-remote-desktop gnome-user-share gnome-tweaks
# gnome-* libraries (keyring, online-accounts, desktop3/4) and standalone
# utilities (Disks, System Monitor) stay: shared deps, not part of the shell.
dnf5 remove -y \
    gnome-shell \
    'gnome-shell-extension-*' \
    gnome-terminal \
    gnome-software \
    gnome-control-center \
    nautilus \
    gdm \
    gnome-tour \
    gnome-user-docs \
    gnome-remote-desktop \
    gnome-user-share \
    gnome-tweaks

echo "GNOME desktop removed"
echo "::endgroup::"

echo "::group:: Install COSMIC Desktop"

# Group pulls cosmic-session + core apps; cosmic-session requires
# cosmic-greeter and xdg-desktop-portal-cosmic.
dnf5 install -y @cosmic-desktop

echo "COSMIC desktop installed"
echo "::endgroup::"

echo "::group:: Configure dock"

# Dock favorites land after the cosmic RPMs, not in 10-build.sh: cosmic-applets
# ships its own default schema under /usr/share/cosmic, and a file written
# before the package installs is at best pointless and at worst a package/file
# conflict. cosmic-config falls back to this path per key, so it only supplies a
# value for users who have not pinned apps themselves.
COSMIC_APP_LIST_DIR=/usr/share/cosmic/com.system76.CosmicAppList/v1
mkdir -p "$COSMIC_APP_LIST_DIR"
install -m 0644 /ctx/overrides/cosmic/com.system76.CosmicAppList/v1/favorites \
    "$COSMIC_APP_LIST_DIR/favorites"

# Same trap as build/30-browsers.sh: an unmatched ID does not vanish from the
# dock, it renders as a broken placeholder icon. Verify the OS-shipped entries.
for desktop_id in com.system76.CosmicFiles com.system76.CosmicTerm; do
    if ! [[ -f /usr/share/applications/"${desktop_id}.desktop" ]]; then
        echo "WARNING: ${desktop_id}.desktop not found; the dock will show a"
        echo "broken icon for it. List what is installed:"
        ls /usr/share/applications/*osmic* 2>/dev/null || true
        echo "Then update overrides/cosmic/com.system76.CosmicAppList/v1/favorites"
        echo "and custom/ujust/custom-migrate.just"
    fi
done

echo "Dock configured"
echo "::endgroup::"

echo "::group:: Configure display manager"

# cosmic-greeter.service is enabled by Fedora's 85-display-manager preset, but
# enable explicitly so a container build (which may not run presets) is safe.
systemctl enable cosmic-greeter

echo "::endgroup::"

echo "::group:: Verify session"

# No GDM anymore: without a cosmic wayland session entry the machine boots to
# no desktop. Fail loudly instead.
if ! grep -q "Exec=/usr/bin/start-cosmic" /usr/share/wayland-sessions/cosmic.desktop; then
    echo "ERROR: cosmic-session wayland entry not found"
    ls -l /usr/share/wayland-sessions/ || true
    exit 1
fi
if [ ! -x /usr/bin/start-cosmic ]; then
    echo "ERROR: /usr/bin/start-cosmic missing"
    exit 1
fi

echo "COSMIC desktop installation complete!"
echo "::endgroup::"
