# vim: set ft=make :
####################
### custom-apps.just
####################
## Example application installation commands
## See .agents/skills/finpilot-custom/SKILL.md for runtime layer guidance

# Install the GUI casks (1Password app + CLI, Zed) and wire 1Password native
# messaging into the native RPM browsers. Needs a terminal: cask postflight
# uses sudo for setgid/setuid bits, polkit, groupadd, and the allowlist.
[group('Apps')]
install-apps:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing GUI applications via Homebrew casks..."
    brew bundle --file /usr/share/ublue-os/homebrew/apps.Brewfile

    # The casks write native messaging manifests and their wrapper into
    # ~/.mozilla and ~/.config/BraveSoftware/Brave-Browser. LibreWolf and Brave
    # Origin only scan their own directories, so mirror the files into them.
    mirror() {
        if [[ ! -d "$1" ]]; then
            echo "  Skipping mirror: $1 not written by the casks."
            return 0
        fi
        mkdir -p "$2"
        cp -f "$1"/*.json "$1"/1PasswordWrapper.sh "$2"/
        chmod 755 "$2"/1PasswordWrapper.sh
    }
    mirror "$HOME/.mozilla/native-messaging-hosts" "$HOME/.librewolf/native-messaging-hosts"
    mirror "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts" \
           "$HOME/.config/BraveSoftware/Brave-Origin/NativeMessagingHosts"
    # ponytail: copies go stale after `brew upgrade`; re-run this recipe to refresh.

    # LibreWolf is not in 1Password's shipped browser allowlist.
    if ! grep -qxF librewolf /etc/1password/custom_allowed_browsers 2>/dev/null; then
        printf 'librewolf\n' | sudo tee -a /etc/1password/custom_allowed_browsers >/dev/null
    fi

    echo "Restart 1Password, then enable each browser under Settings -> Integrations."

# Install default applications via Homebrew
[group('Apps')]
install-default-apps:
    #!/usr/bin/env bash
    echo "Installing default applications via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile

# Install development tools via Homebrew
[group('Apps')]
install-dev-tools:
    #!/usr/bin/env bash
    echo "Installing development tools via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile

# Install fonts via Homebrew
[group('Apps')]
install-fonts:
    #!/usr/bin/env bash
    echo "Installing fonts via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/fonts.Brewfile

# Install all Brewfiles at once
[group('Apps')]
install-all-brew:
    #!/usr/bin/env bash
    echo "Installing all applications from Brewfiles..."
    ujust install-apps
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile
    brew bundle --file /usr/share/ublue-os/homebrew/fonts.Brewfile

# Install JetBrains Toolbox for managing JetBrains IDEs
[group('Apps')]
install-jetbrains-toolbox:
    #!/usr/bin/env bash
    echo "Installing JetBrains Toolbox..."
    pushd "$(mktemp -d)"
    echo "Fetching latest version..."
    curl -sSfL -o releases.json "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
    BUILD_VERSION=$(jq -r '.TBA[0].build' ./releases.json)
    DOWNLOAD_LINK=$(jq -r '.TBA[0].downloads.linux.link' ./releases.json)
    CHECKSUM_LINK=$(jq -r '.TBA[0].downloads.linux.checksumLink' ./releases.json)
    echo "Installing JetBrains Toolbox ${BUILD_VERSION}"
    curl -sSfL -O "${DOWNLOAD_LINK}"
    curl -sSfL "${CHECKSUM_LINK}" | sha256sum -c
    tar zxf jetbrains-toolbox-"${BUILD_VERSION}".tar.gz
    mkdir -p $HOME/.local/share/JetBrains/ToolboxApp/
    mv jetbrains-toolbox-"${BUILD_VERSION}"/* $HOME/.local/share/JetBrains/ToolboxApp/
    popd
    echo "Launching JetBrains Toolbox..."
    $HOME/.local/share/JetBrains/ToolboxApp/bin/jetbrains-toolbox

# Shortcut for install-jetbrains-toolbox
[group('Apps')]
jetbrains-toolbox:
    @ujust install-jetbrains-toolbox

# Install a Flatpak application from Flathub
[group('Apps')]
install-flatpak APP_ID:
    #!/usr/bin/bash
    echo "Installing {{ APP_ID }} from Flathub..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub {{ APP_ID }}

# Example: Install VSCode via Flatpak
[group('Apps')]
install-vscode:
    ujust install-flatpak com.visualstudio.code

# Example: Install GIMP via Flatpak
[group('Apps')]
install-gimp:
    ujust install-flatpak org.gimp.GIMP
