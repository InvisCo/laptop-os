#!/usr/bin/env bats
# Tests for the permission contract inside the install-apps recipe.
#
# The 1Password casks apply root ownership and setgid/setuid bits through
# Homebrew `sudo:` postflight steps. Declining the password prompt leaves the
# payload user-owned and world-writable, which breaks browser integration
# (the app authenticates the helper through its peer group) and is a
# privilege-escalation vector. The recipe must therefore repair the contract
# and abort loudly when the repair does not land.
#
# The contract lives in a bash block inside custom/ujust/custom-apps.just, so
# this test extracts fix() from that file and drives it with a sudo shim.
#
# Run with: bats tests/template/install-apps_test.bats

RECIPE="${BATS_TEST_DIRNAME}/../../custom/ujust/custom-apps.just"

setup() {
    WORKDIR="$(mktemp -d)"
    BIN="${WORKDIR}/bin"
    mkdir -p "${BIN}"
    # fix() is extracted verbatim from the recipe; no reimplementation here.
    awk '/^[[:space:]]*fix\(\)[[:space:]]*\{/{on=1} on{print} on&&/^[[:space:]]*\}[[:space:]]*$/{exit}' \
        "${RECIPE}" > "${WORKDIR}/fix.sh"
    cat > "${BIN}/sudo" <<'SHIM'
#!/usr/bin/bash
if [[ "${SUDO_SHIM_FAIL:-0}" == 1 ]]; then
    echo "sudo: effective uid is not 0" >&2
    exit 1
fi
exec "$@"
SHIM
    chmod +x "${BIN}/sudo"
    export PATH="${BIN}:/usr/bin:/bin"
}

teardown() {
    rm -rf "${WORKDIR}"
}

@test "install-apps fixes a helper left at the Homebrew default mode" {
    target="${WORKDIR}/1Password-BrowserSupport"
    : > "${target}"
    chmod 777 "${target}"
    run bash -c 'set -euo pipefail; source "$1"; fix "$2" "$USER:$(id -gn)" 2755' \
        _ "${WORKDIR}/fix.sh" "${target}"
    [ "${status}" -eq 0 ]
    [ "$(stat -c '%a' "${target}")" = "2755" ]
}

@test "install-apps skips the repair when the contract already holds" {
    target="${WORKDIR}/chrome-sandbox"
    : > "${target}"
    chmod 4755 "${target}"
    SUDO_SHIM_FAIL=1 run bash -c 'set -euo pipefail; source "$1"; fix "$2" "$USER:$(id -gn)" 4755' \
        _ "${WORKDIR}/fix.sh" "${target}"
    [ "${status}" -eq 0 ]
}

@test "install-apps fails loudly when the repair cannot be applied" {
    target="${WORKDIR}/op"
    : > "${target}"
    chmod 755 "${target}"
    SUDO_SHIM_FAIL=1 run bash -c 'set -euo pipefail; source "$1"; fix "$2" "$USER:$(id -gn)" 2755' \
        _ "${WORKDIR}/fix.sh" "${target}"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"FAIL"* ]]
    [[ "${output}" == *"${target}"* ]]
}

@test "install-apps asserts the three 1Password contracts" {
    recipe="${BATS_TEST_DIRNAME}/../../custom/ujust/custom-apps.just"
    run grep -qE 'fix "\$P/bin/1Password-BrowserSupport"[[:space:]]+root:onepassword[[:space:]]+2755' "${recipe}"
    [ "${status}" -eq 0 ]
    run grep -qE 'fix "\$P/bin/op"[[:space:]]+root:onepassword-cli[[:space:]]+2755' "${recipe}"
    [ "${status}" -eq 0 ]
    # chrome-sandbox is not a cask binary, so it is not linked into bin:
    # it sits next to the Electron payload, which is where Electron looks.
    run grep -qE 'APP_DIR="\$\(dirname "\$\(readlink -f "\$P/bin/1password"\)"\)"' "${recipe}"
    [ "${status}" -eq 0 ]
    run grep -qE 'fix "\$APP_DIR/chrome-sandbox"[[:space:]]+root:root[[:space:]]+4755' "${recipe}"
    [ "${status}" -eq 0 ]
}

@test "install-apps names a missing target instead of comparing an empty stat" {
    run bash -c 'set -euo pipefail; source "$1"; fix "$2" "$USER:$(id -gn)" 2755' \
        _ "${WORKDIR}/fix.sh" "${WORKDIR}/no-such-binary"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"not found"* ]]
}

@test "install-apps trusts and taps the cask tap before bundling" {
    recipe="${BATS_TEST_DIRNAME}/../../custom/ujust/custom-apps.just"
    run grep -qF 'brew trust ublue-os/tap' "${recipe}"
    [ "${status}" -eq 0 ]
    trust_line="$(grep -n 'brew trust ublue-os/tap' "${recipe}" | head -1 | cut -d: -f1)"
    bundle_line="$(grep -n 'brew bundle --file /usr/share/ublue-os/homebrew/apps.Brewfile' "${recipe}" | head -1 | cut -d: -f1)"
    [ -n "${bundle_line}" ]
    [ "${trust_line}" -lt "${bundle_line}" ]
}

@test "apps.Brewfile qualifies every cask token with its tap" {
    brewfile="${BATS_TEST_DIRNAME}/../../custom/brew/apps.Brewfile"
    [ "$(grep -c '^[[:space:]]*cask "ublue-os/tap/' "${brewfile}")" -eq 3 ]
    [ "$(grep -c '^[[:space:]]*cask "[^"]*"' "${brewfile}")" -eq 3 ]
    grep -qF 'tap "ublue-os/tap", trusted: true' "${brewfile}"
}
