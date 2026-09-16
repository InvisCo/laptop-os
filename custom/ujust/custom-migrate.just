# vim: set ft=make :
#########################
### custom-migrate.just
#########################
## Bluefin → laptop-os migration. Single entry point for first boot after
## `bootc switch ghcr.io/.../laptop-os:stable`. Re-runnable (sentinel-gated,
## every phase idempotent). User-level tools only by rule — brew/flatpak/gsettings.

# Apply the laptop-os dock layout to the live user DB.
# Image gschema defaults only reach new users; migrated users need this.
[group('System')]
set-dock-layout:
    #!/usr/bin/env bash
    set -euo pipefail
    FAVORITES="['app.zen_browser.zen.desktop', 'librewolf.desktop', 'brave-origin.desktop', 'org.gnome.Nautilus.desktop', 'eu.betterbird.Betterbird.desktop', 'org.gnome.Ptyxis.desktop', 'org.gnome.gitlab.cheywood.Buffer.desktop']"
    gsettings set org.gnome.shell favorite-apps "$FAVORITES"
    echo "Dock layout applied. Missing IDs vanish silently — verify with:"
    echo "  gsettings get org.gnome.shell favorite-apps"

# Full Bluefin → laptop-os migration. Prompts per phase; yes=1 skips prompts.
[group('System')]
migrate-from-bluefin yes="0":
    #!/usr/bin/env bash
    set -euo pipefail
    source /usr/lib/ujust/ujust.sh
    MARKER="$HOME/.config/laptop-os/migrate-from-bluefin.done"
    ASK="{{ yes }}"

    confirm() {
        if [[ "$ASK" == "1" ]]; then return 0; fi
        gum confirm "$1"
    }

    if [[ -f "$MARKER" ]]; then
        echo "Migration already ran ($(cat "$MARKER")). Re-running anyway."
    fi

    echo "::group:: Preflight"
    if ! systemctl is-active --quiet brew-setup.service && [[ ! -x "$HOME/.linuxbrew/bin/brew" && ! -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
        echo "WARNING: brew not ready yet (brew-setup.service not done). Run this again after first-boot settles."
    fi
    if ! ping -c1 -W3 flathub.org >/dev/null 2>&1; then
        echo "WARNING: no network — flatpak/brew phases will fail. Continuing anyway."
    fi
    echo "::endgroup::"

    echo "::group:: Brew bundles"
    if confirm "Install Brew bundles (default + dev + fonts)?"; then
        just --justfile "{{ justfile() }}" install-all-brew
    fi
    echo "::endgroup::"

    echo "::group:: Flatpaks"
    if confirm "Top up Flatpaks from preinstall list?"; then
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        for app in app.zen_browser.zen eu.betterbird.Betterbird org.gimp.GIMP org.inkscape.Inkscape org.libreoffice.LibreOffice org.kde.okular org.onlyoffice.desktopeditors com.protonvpn.www org.rncbc.qpwgraph com.rawtherapee.RawTherapee org.remmina.Remmina com.rustdesk.RustDesk; do
            if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
                echo "  $app already installed, skipping."
            else
                echo "  Installing $app..."
                flatpak install -y flathub "$app" || echo "  FAILED: $app (continuing)"
            fi
        done
    fi
    echo "::endgroup::"

    echo "::group:: LibreWolf overrides"
    if confirm "Install LibreWolf loosened-defaults overrides?"; then
        just --justfile "{{ justfile() }}" laptop-os-librewolf-overrides
    fi
    echo "::endgroup::"

    echo "::group:: Groups"
    if confirm "Add yourself to libvirt group (needs logout)?"; then
        just --justfile "{{ justfile() }}" configure-dev-groups
    fi
    echo "::endgroup::"

    echo "::group:: Dock"
    if confirm "Apply laptop-os dock layout to your user?"; then
        just --justfile "{{ justfile() }}" set-dock-layout
    fi
    echo "::endgroup::"

    echo "::group:: Dotfiles"
    if command -v chezmoi >/dev/null 2>&1; then
        if confirm "Run chezmoi init/apply for dotfiles?"; then
            if [[ -d "$HOME/.local/share/chezmoi" ]]; then
                chezmoi apply
            else
                echo "No chezmoi source found. Run: chezmoi init <your-repo> && chezmoi apply"
            fi
        fi
    else
        echo "chezmoi not installed (brew bundle above provides it). Skipping."
    fi
    echo "::endgroup::"

    echo "::group:: Printers"
    if confirm "Set up Epson CUPS queues (drivers are baked in)?"; then
        echo "Add queues in GNOME Settings → Printers, or e.g.:"
        echo "  lpadmin -p Epson-L355 -E -m everywhere -v <device-uri>"
        echo "Then print a test page per queue."
    fi
    echo "::endgroup::"

    echo "::group:: 1Password checklist (manual)"
    echo "  1. Sign in to 1Password (app + browser extension pre-wired)."
    echo "  2. Enable Settings → Browser → 'Integrate with 1Password in your browser' (LibreWolf trust is baked in)."
    echo "  3. op signin, enable SSH agent if used."
    echo "  4. virsh list --all (virt check); flatpak list | grep -i zen (Zen check)."
    echo "::endgroup::"

    mkdir -p "$(dirname "$MARKER")"
    date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKER"
    echo "Migration done. Marker: $MARKER"

# Shortcut alias (migrate- verb is new; setup- fits existing taxonomy)
[group('System')]
setup-laptop yes="0":
    @just --justfile "{{ justfile() }}" migrate-from-bluefin "{{ yes }}"
