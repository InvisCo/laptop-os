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

    # Trust and tap before bundling: `brew bundle` resolves cask tokens while
    # it loads the file, before its own tap lines run.
    brew trust ublue-os/tap >/dev/null 2>&1 || brew trust ublue-os/tap
    brew tap ublue-os/tap
    echo "Installing GUI applications via Homebrew casks..."
    brew bundle --file /usr/share/ublue-os/homebrew/apps.Brewfile

    # The casks apply root ownership and setgid/setuid bits through Homebrew
    # `sudo:` postflight steps. Decline the password prompt and they silently
    # no-op, leaving the payload user-owned: 1Password authenticates the
    # browser through the helper's peer group, so a helper that is not
    # root:onepassword 2755 is rejected with "invalid group attempted to
    # connect", and a world-writable user-owned helper is a privilege
    # escalation vector. Repair, then assert - a deploy that ran is not a
    # deploy that worked.
    fix() {  # <bin> <user:group> <mode>
        local target; target="$(readlink -f "$1")"
        if [[ ! -e "${target}" ]]; then
            echo "FAIL: $1 not found at ${target} - the cask did not install it." >&2
            exit 1
        fi
        if [[ "$(stat -c '%U:%G %a' "${target}")" != "$2 $3" ]]; then
            echo "  Repairing $1 -> $2 $3"
            sudo chown "$2" "${target}" || true
            sudo chmod "$3" "${target}" || true
        fi
        if [[ "$(stat -c '%U:%G %a' "$(readlink -f "$1")")" != "$2 $3" ]]; then
            echo "FAIL: $1 is $(stat -c '%U:%G %a' "${target}"), not $2 $3." >&2
            echo "       1Password cannot authenticate the browser. Re-run with sudo available." >&2
            exit 1
        fi
    }
    P="$(brew --prefix)"
    # chrome-sandbox is not a declared cask binary, so it is not linked into
    # bin: it lives next to the Electron payload, which is where Electron looks.
    APP_DIR="$(dirname "$(readlink -f "$P/bin/1password")")"
    fix "$P/bin/1Password-BrowserSupport" root:onepassword     2755
    fix "$P/bin/op"                       root:onepassword-cli 2755
    fix "$APP_DIR/chrome-sandbox"         root:root            4755

    # 1Password authenticates the browser through the connecting process's
    # effective group, so the group has to exist with a GID >= 1000. A GID
    # below GID_MIN is rejected with "invalid group attempted to connect", and
    # on this image it also collides with the dynamic systemd users
    # systemd-coredump/pipewire, which usermod cannot move. The image pins both
    # GIDs in /usr/lib/sysusers.d/1password.conf, so this only repairs a host
    # where the RPM's groupadd -r already allocated one.
    ensure_group() {  # <name> <gid>
        local name="$1" want="$2" have=""
        # getent exits non-zero for a missing group; under `set -e -o pipefail`
        # that would abort the recipe before it can create the group.
        have="$(getent group "${name}" | cut -d: -f3 || true)"
        if [[ -z "${have}" ]]; then
            echo "  Creating group ${name} (gid ${want})"
            sudo groupadd -g "${want}" "${name}"
        elif [[ "${have}" != "${want}" ]]; then
            echo "  ${name} has gid ${have}, 1Password needs ${want}"
            if sudo groupmod -g "${want}" "${name}"; then
                echo "  Repaired ${name} -> gid ${want}"
            else
                echo "FAIL: cannot move ${name} off gid ${have}." >&2
                echo "      Another account holds that gid; a dynamic systemd user" >&2
                echo "      cannot be moved with usermod. Recreate the group instead:" >&2
                echo "        sudo sed -i '/^${name}:/d' /etc/group" >&2
                echo "        sudo groupadd -g ${want} ${name}" >&2
                echo "        sudo usermod -aG ${name} \$USER" >&2
                exit 1
            fi
        fi
    }
    ensure_group onepassword 1500
    ensure_group onepassword-cli 1501

    # The app validates the peer's group against its own supplementary groups,
    # so the desktop session must contain them too. Group membership is fixed at
    # login, so the app must be started from a session opened after this.
    if ! id -nG | tr ' ' '\n' | grep -qx onepassword; then
        sudo usermod -aG onepassword,onepassword-cli "${USER}"
        echo "  Added ${USER} to onepassword,onepassword-cli."
        echo "  Log out and back in (or start a new session) before launching 1Password."
    fi

    # 1Password-BrowserSupport refuses to start when ptrace_scope is 0
    # ("Yama is absent or ptrace_scope is set to 0"), because its anti-tampering
    # checks rely on Yama. The image sets 1 in /usr/lib/sysctl.d; assert it so a
    # host that overrode it is reported instead of silently failing later.
    if [[ "$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || echo 0)" -lt 1 ]]; then
        echo "FAIL: kernel.yama.ptrace_scope is $(cat /proc/sys/kernel/yama/ptrace_scope)." >&2
        echo "      1Password-BrowserSupport aborts unless it is >= 1." >&2
        echo "      Fix: sudo sysctl -w kernel.yama.ptrace_scope=1" >&2
        exit 1
    fi

    # Native browsers need a manifest that points straight at the helper: there
    # is no sandbox to escape, so no wrapper. The cask writes its own manifest
    # plus a wrapper into ~/.mozilla and BraveSoftware/Brave-Browser, and the app
    # rewrites them at every launch, so write ours into the directories the
    # browsers actually scan and keep them read-only afterwards.
    native_manifest() {  # <dir> <kind:chromium|gecko>
        local dir="$1" kind="$2" manifest
        mkdir -p "${dir}"
        manifest="${dir}/com.1password.1password.json"
        printf '%s\n' '{' > "${manifest}"
        printf '%s\n' '    "name": "com.1password.1password",' >> "${manifest}"
        printf '%s\n' '    "description": "1Password BrowserSupport",' >> "${manifest}"
        printf '%s\n' "    \"path\": \"$P/bin/1Password-BrowserSupport\"," >> "${manifest}"
        printf '%s\n' '    "type": "stdio",' >> "${manifest}"
        if [[ "${kind}" == chromium ]]; then
            printf '%s\n' '    "allowed_origins": [' >> "${manifest}"
            printf '%s\n' '        "chrome-extension://nlpaeekllejnmhoonlpcefpfnpbajbpe/",' >> "${manifest}"
            printf '%s\n' '        "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/",' >> "${manifest}"
            printf '%s\n' '        "chrome-extension://hjlinigoblmkhjejkmbegnoaljkphmgo/",' >> "${manifest}"
            printf '%s\n' '        "chrome-extension://gejiddohjgogedgjnonbofjigllpkmbf/",' >> "${manifest}"
            printf '%s\n' '        "chrome-extension://khgocmkkpikpnmmkgmdnfckapcdkgfaf/",' >> "${manifest}"
            printf '%s\n' '        "chrome-extension://dppgmdbiimibapkepcbdbmkaabgiofem/"' >> "${manifest}"
            printf '%s\n' '    ]' >> "${manifest}"
        else
            printf '%s\n' '    "allowed_extensions": [' >> "${manifest}"
            printf '%s\n' '        "{0a75d802-9aed-41e7-8daa-24c067386e82}",' >> "${manifest}"
            printf '%s\n' '        "{25fc87fa-4d31-4fee-b5c1-c32a7844c063}",' >> "${manifest}"
            printf '%s\n' '        "{d634138d-c276-4fc8-924b-40a0ea21d284}"' >> "${manifest}"
            printf '%s\n' '    ]' >> "${manifest}"
        fi
        printf '%s\n' '}' >> "${manifest}"
        chmod 644 "${manifest}"
    }
    for dir in \
        "$HOME/.config/BraveSoftware/Brave-Origin/NativeMessagingHosts" \
        "$HOME/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"; do
        [[ -x "/usr/bin/brave-origin" ]] && native_manifest "${dir}" chromium
    done
    for dir in \
        "$HOME/.librewolf/native-messaging-hosts" \
        "$HOME/.mozilla/native-messaging-hosts"; do
        [[ -x "/usr/bin/librewolf" ]] && native_manifest "${dir}" gecko
    done

    # 1Password only talks to allowlisted browser binaries, and the cask seeds
    # the file with upstream's list. Add this image's browsers.
    for browser in brave-origin librewolf; do
        [[ -x "/usr/bin/${browser}" ]] || continue
        if ! grep -qxF "${browser}" /etc/1password/custom_allowed_browsers 2>/dev/null; then
            printf '%s\n' "${browser}" | sudo tee -a /etc/1password/custom_allowed_browsers >/dev/null
        fi
    done

    echo "Restart 1Password, then enable each browser under Settings -> Integrations."
    echo "Verify with:"
    echo "  grep -iE 'verified successfully|invalid group' ~/.config/1Password/logs/1Password_rCURRENT.log | tail"

# Wire 1Password browser integration for a Flatpak browser (FlyinPancake bridge).
# The app stays native; only the browser moves into the sandbox. Chromium strips
# the helper's setgid bit on native launches (NoNewPrivs), so the app rejects the
# peer as "invalid group attempted to connect". Spawned through
# flatpak-session-helper the setgid survives. Needs a terminal: the allowlist
# append uses sudo, and the Flatpak install may prompt.
# Usage: ujust install-1password-bridge [HELPER] [FLATPAK_ID]
# HELPER defaults to the RPM payload, then the Homebrew link.
[group('Apps')]
install-1password-bridge HELPER="" FLATPAK_ID="io.gitlab.librewolf-community":
    #!/usr/bin/env bash
    set -euo pipefail

    bridge_helper() {  # [$1 explicit path] -> prints the helper to use
        if [[ -n "${1:-}" ]]; then
            if [[ -x "$1" ]]; then
                printf '%s\n' "$1"
                return 0
            fi
            echo "FAIL: helper $1 is not executable." >&2
            exit 1
        fi
        local prefix=""
        prefix="$(brew --prefix 2>/dev/null || true)"
        for candidate in \
            /usr/lib/opt/1Password/1Password-BrowserSupport \
            /opt/1Password/1Password-BrowserSupport \
            "${prefix}/bin/1Password-BrowserSupport" \
            /home/linuxbrew/.linuxbrew/bin/1Password-BrowserSupport; do
            if [[ -x "${candidate}" ]]; then
                printf '%s\n' "${candidate}"
                return 0
            fi
        done
        echo "FAIL: no 1Password-BrowserSupport found - install the native app first." >&2
        exit 1
    }

    bridge_manifest_dirs() {  # <flatpak-id> -> every dir Gecko scans, one per line
        local id="$1" base d sub
        base="$HOME/.var/app/${id}"
        shopt -s dotglob nullglob
        for d in "${base}/"*/; do
            [[ -d "${d}native-messaging-hosts" ]] && printf '%s\n' "${d}native-messaging-hosts"
            for sub in "${d}"*/; do
                [[ -d "${sub}native-messaging-hosts" ]] && printf '%s\n' "${sub}native-messaging-hosts"
            done
        done
        # The two locations a fresh profile always has, plus the profile dir:
        # Gecko reads the user-level dir, the XDG config dir, and per-profile.
        printf '%s\n' "${base}/.mozilla/native-messaging-hosts"
        printf '%s\n' "${base}/config/mozilla/native-messaging-hosts"
        for sub in "${base}/config/"*/*/; do
            [[ -f "${sub}profiles.ini" ]] && printf '%s\n' "${sub}native-messaging-hosts"
        done
        shopt -u dotglob nullglob
    }

    bridge_write() {  # <helper> <flatpak-id> -> writes wrapper + manifests
        local helper="$1" id="$2"
        flatpak override --user --talk-name=org.freedesktop.Flatpak "${id}"
        local bindir="$HOME/.var/app/${id}/data/bin"
        mkdir -p "${bindir}"
        # No heredocs: just cannot parse <<EOF blocks, so both files are
        # assembled with printf. Backslash escapes render literal dollars.
        #
        # exec the helper DIRECTLY. Routing through `sg onepassword -c ...`
        # makes the helper exec from a shell that already holds the group, so
        # there is no privilege transition, AT_SECURE stays 0, and the helper
        # aborts with "process detected it was running without libc's security".
        printf '%s\n' '#!/bin/bash' > "${bindir}/1password-wrapper.sh"
        printf '%s\n' "# 1Password native messaging host bridge for a Flatpak browser." >> "${bindir}/1password-wrapper.sh"
        printf '%s\n' "if [ \"\${container-}\" = flatpak ]; then" >> "${bindir}/1password-wrapper.sh"
        printf '%s\n' "    exec flatpak-spawn --host \"${helper}\" \"\$@\"" >> "${bindir}/1password-wrapper.sh"
        printf '%s\n' 'else' >> "${bindir}/1password-wrapper.sh"
        printf '%s\n' "    exec \"${helper}\" \"\$@\"" >> "${bindir}/1password-wrapper.sh"
        printf '%s\n' 'fi' >> "${bindir}/1password-wrapper.sh"
        chmod 755 "${bindir}/1password-wrapper.sh"
        local mdir manifest
        while IFS= read -r mdir; do
            mkdir -p "${mdir}"
            manifest="${mdir}/com.1password.1password.json"
            printf '%s\n' '{' > "${manifest}"
            printf '%s\n' '    "name": "com.1password.1password",' >> "${manifest}"
            printf '%s\n' '    "description": "1Password BrowserSupport",' >> "${manifest}"
            printf '%s\n' "    \"path\": \"${bindir}/1password-wrapper.sh\"," >> "${manifest}"
            printf '%s\n' '    "type": "stdio",' >> "${manifest}"
            printf '%s\n' '    "allowed_extensions": [' >> "${manifest}"
            printf '%s\n' '        "{0a75d802-9aed-41e7-8daa-24c067386e82}",' >> "${manifest}"
            printf '%s\n' '        "{25fc87fa-4d31-4fee-b5c1-c32a7844c063}",' >> "${manifest}"
            printf '%s\n' '        "{d634138d-c276-4fc8-924b-40a0ea21d284}"' >> "${manifest}"
            printf '%s\n' '    ]' >> "${manifest}"
            printf '%s\n' '}' >> "${manifest}"
            chmod 644 "${manifest}"
        done < <(bridge_manifest_dirs "${id}")
    }

    bridge_allowlist() {
        if ! grep -qxF 'flatpak-session-helper' /etc/1password/custom_allowed_browsers 2>/dev/null; then
            printf '%s\n' 'flatpak-session-helper' | sudo tee -a /etc/1password/custom_allowed_browsers >/dev/null
        fi
    }

    HELPER="$(bridge_helper "{{ HELPER }}")"
    ID="{{ FLATPAK_ID }}"
    if ! flatpak list --app --columns=application 2>/dev/null | grep -qxF "${ID}"; then
        echo "Installing ${ID} from Flathub..."
        flatpak install -y flathub "${ID}"
    fi
    bridge_write "${HELPER}" "${ID}"
    bridge_allowlist

    echo "Restart 1Password and the Flatpak browser, then click the extension."
    echo "Verify with:"
    echo "  grep -iE 'verified successfully|invalid group' ~/.config/1Password/logs/1Password_rCURRENT.log | tail"

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
