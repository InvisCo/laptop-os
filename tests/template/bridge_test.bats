#!/usr/bin/env bats
# Tests for the Flatpak bridge inside the install-1password-bridge recipe.
#
# Native Chromium launches strip the helper's setgid bit (NoNewPrivs), so the
# app rejects the peer as "invalid group attempted to connect". Spawned through
# flatpak-session-helper the setgid survives: the recipe therefore writes the
# FlyinPancake layout (in-sandbox wrapper + manifest, talk-name override,
# flatpak-session-helper allowlist) instead of touching the native browsers.
#
# Functions are extracted verbatim from custom/ujust/custom-apps.just and driven
# with shims. The extractor stops at the 4-space-indented closing brace because
# the JSON heredoc inside bridge_write contains a column-zero `}` of its own.
#
# Run with: bats tests/template/bridge_test.bats

RECIPE="${BATS_TEST_DIRNAME}/../../custom/ujust/custom-apps.just"

extract() {
    awk -v fn="$1" '
        $0 ~ "^[[:space:]]*"fn"\\(\\)[[:space:]]*\\{" {on=1}
        on {print}
        on && $0 ~ "^    \\}[[:space:]]*$" {exit}
    ' "${RECIPE}" > "$2"
}

setup() {
    WORKDIR="$(mktemp -d)"
    BIN="${WORKDIR}/bin"
    mkdir -p "${BIN}" "${WORKDIR}/home"
    extract bridge_helper "${WORKDIR}/bridge_helper.sh"
    extract bridge_manifest_dirs "${WORKDIR}/bridge_manifest_dirs.sh"
    extract bridge_write "${WORKDIR}/bridge_write.sh"
    cat > "${BIN}/flatpak" <<'SHIM'
#!/usr/bin/bash
exit 0
SHIM
    chmod +x "${BIN}/flatpak"
    export PATH="${BIN}:/usr/bin:/bin"
    export HOME="${WORKDIR}/home"
}

teardown() {
    rm -rf "${WORKDIR}"
}

@test "bridge_helper prefers an explicit executable helper" {
    target="${WORKDIR}/1Password-BrowserSupport"
    : > "${target}"
    chmod +x "${target}"
    run bash -c 'set -euo pipefail; source "$1"; bridge_helper "$2"' \
        _ "${WORKDIR}/bridge_helper.sh" "${target}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "${target}" ]
}

@test "bridge_helper fails loudly on a missing explicit helper" {
    run bash -c 'set -euo pipefail; source "$1"; bridge_helper "$2"' \
        _ "${WORKDIR}/bridge_helper.sh" "${WORKDIR}/no-such-helper"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"FAIL"* ]]
}

@test "bridge_helper searches the RPM payload before the Homebrew link" {
    recipe="${BATS_TEST_DIRNAME}/../../custom/ujust/custom-apps.just"
    rpm_line="$(grep -n '/usr/lib/opt/1Password/1Password-BrowserSupport' "${recipe}" | head -1 | cut -d: -f1)"
    brew_line="$(grep -n 'linuxbrew.*1Password-BrowserSupport' "${recipe}" | head -1 | cut -d: -f1)"
    [ -n "${rpm_line}" ]
    [ -n "${brew_line}" ]
    [ "${rpm_line}" -lt "${brew_line}" ]
}

@test "bridge_manifest_dirs lists the user-level and XDG locations Gecko scans" {
    run bash -c 'set -euo pipefail; source "$1"; bridge_manifest_dirs "$2"' \
        _ "${WORKDIR}/bridge_manifest_dirs.sh" "io.gitlab.librewolf-community"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *".var/app/io.gitlab.librewolf-community/.mozilla/native-messaging-hosts"* ]]
    [[ "${output}" == *"config/mozilla/native-messaging-hosts"* ]]
}

@test "bridge_manifest_dirs includes a discovered profile directory" {
    mkdir -p "${HOME}/.var/app/io.gitlab.librewolf-community/config/librewolf/librewolf"
    touch "${HOME}/.var/app/io.gitlab.librewolf-community/config/librewolf/librewolf/profiles.ini"
    run bash -c 'set -euo pipefail; source "$1"; bridge_manifest_dirs "$2"' \
        _ "${WORKDIR}/bridge_manifest_dirs.sh" "io.gitlab.librewolf-community"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"config/librewolf/librewolf/native-messaging-hosts"* ]]
}

@test "bridge_write execs the helper directly through every manifest dir" {
    helper="${WORKDIR}/1Password-BrowserSupport"
    : > "${helper}"
    chmod +x "${helper}"
    run bash -c 'set -euo pipefail; source "$1"; source "$2"; bridge_write "$3" "$4"' \
        _ "${WORKDIR}/bridge_manifest_dirs.sh" "${WORKDIR}/bridge_write.sh" \
        "${helper}" "io.gitlab.librewolf-community"
    [ "${status}" -eq 0 ]
    wrapper="${HOME}/.var/app/io.gitlab.librewolf-community/data/bin/1password-wrapper.sh"
    [ -x "${wrapper}" ]
    # exec keeps the browser as the helper's parent, and keeps AT_SECURE set.
    grep -qF "exec flatpak-spawn --host \"${helper}\"" "${wrapper}"
    grep -qF "exec \"${helper}\"" "${wrapper}"
    count="$(grep -rl '"name": "com.1password.1password"' \
        "${HOME}/.var/app/io.gitlab.librewolf-community" | wc -l)"
    [ "${count}" -ge 2 ]
    grep -qF "\"path\": \"${wrapper}\"" "$(grep -rl '"name": "com.1password.1password"' \
        "${HOME}/.var/app/io.gitlab.librewolf-community" | head -1)"
}

@test "install-1password-bridge grants the Flatpak bus and allowlists the helper" {
    recipe="${BATS_TEST_DIRNAME}/../../custom/ujust/custom-apps.just"
    run grep -qF 'flatpak override --user --talk-name=org.freedesktop.Flatpak' "${recipe}"
    [ "${status}" -eq 0 ]
    run grep -qF "flatpak-session-helper' /etc/1password/custom_allowed_browsers" "${recipe}"
    [ "${status}" -eq 0 ]
    run grep -qF 'install-1password-bridge HELPER="" FLATPAK_ID="io.gitlab.librewolf-community"' "${recipe}"
    [ "${status}" -eq 0 ]
}

@test "LibreWolf is not preinstalled as a Flatpak (native RPM is the browser)" {
    preinstall="${BATS_TEST_DIRNAME}/../../custom/flatpaks/default.preinstall"
    # Native LibreWolf from build/30-browsers.sh is the primary browser and
    # integrates without a bridge; preinstalling the Flatpak would duplicate it.
    run grep -qF 'io.gitlab.librewolf-community' "${preinstall}"
    [ "${status}" -ne 0 ]
}

@test "the bridge still names LibreWolf as its default Flatpak browser" {
    recipe="${BATS_TEST_DIRNAME}/../../custom/ujust/custom-apps.just"
    run grep -qF 'install-1password-bridge HELPER="" FLATPAK_ID="io.gitlab.librewolf-community"' "${recipe}"
    [ "${status}" -eq 0 ]
}
