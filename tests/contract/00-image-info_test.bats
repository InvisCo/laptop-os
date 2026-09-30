#!/usr/bin/env bats

# Unit tests for build/00-image-info.sh. ROOT_DIR directs the script's image
# filesystem writes into a disposable sandbox.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
IMAGE_INFO_SRC="${SCRIPT_DIR}/../../build/00-image-info.sh"

setup() {
    TEST_ROOT="${BATS_TEST_TMPDIR:-${BATS_TMPDIR}}/image-info.${BATS_TEST_NUMBER:-0}.$$"
    SANDBOX="${TEST_ROOT}/root"
    IMAGE_INFO_JSON="${SANDBOX}/usr/share/ublue-os/image-info.json"
    OS_RELEASE="${SANDBOX}/usr/lib/os-release"

    mkdir -p "$(dirname "${OS_RELEASE}")"
    export ROOT_DIR="${SANDBOX}"
    export IMAGE_NAME="laptop-os"
    export IMAGE_VENDOR="InvisCo"
    export IMAGE_PRETTY_NAME="Laptop OS"
    export UBLUE_IMAGE_TAG="stable"
    export BASE_IMAGE_NAME="bluefin"
    export FEDORA_MAJOR_VERSION="44"

    cat >"${OS_RELEASE}" <<'EOF'
NAME="Fedora Linux"
VERSION="44.20260905.0 (Silverblue)"
ID=fedora
VERSION_ID=44
DEFAULT_HOSTNAME="fedora"
HOME_URL="https://silverblue.fedoraproject.org"
DOCUMENTATION_URL="https://docs.fedoraproject.org/"
SUPPORT_URL="https://ask.fedoraproject.org/"
BUG_REPORT_URL="https://github.com/fedora-silverblue/issue-tracker/issues"
ID_LIKE="fedora"
VARIANT="Silverblue"
VARIANT_ID=silverblue
OSTREE_VERSION='44.20260905.0'
EOF
}

teardown() {
    rm -rf "${TEST_ROOT}"
}

run_script() {
    run bash "${IMAGE_INFO_SRC}"
}

json_field() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "${IMAGE_INFO_JSON}" "$1"
}

@test "00-image-info: writes Bluefin-compatible image metadata" {
    run_script
    [ "$status" -eq 0 ]

    run python3 -m json.tool "${IMAGE_INFO_JSON}"
    [ "$status" -eq 0 ]
    [ "$(json_field image-name)" = "laptop-os" ]
    [ "$(json_field image-vendor)" = "InvisCo" ]
    [ "$(json_field image-ref)" = "ostree-unverified-image:docker://ghcr.io/InvisCo/laptop-os" ]
    [ "$(json_field image-tag)" = "stable" ]
    [ "$(json_field base-image-name)" = "bluefin" ]
    [ "$(json_field fedora-version)" = "44" ]
}

@test "00-image-info: the base image name is the one it was given, not a default" {
    # A default here is how the image came to claim it was silverblue while
    # based on Bluefin. `just build` derives this from the base FROM line and
    # fails rather than passing a placeholder, so the script must not invent one.
    export BASE_IMAGE_NAME="centos-stream"
    run_script
    [ "$status" -eq 0 ]
    [ "$(json_field base-image-name)" = "centos-stream" ]
}

@test "00-image-info: updates existing base os-release identity" {
    export VERSION="44.20260907.1"
    run_script
    [ "$status" -eq 0 ]

    # kernel-install's mkbls builds the GRUB title from NAME + VERSION, and the
    # first occurrence of a key is the one that counts, so these are
    # replacements rather than appends.
    grep -q '^VARIANT_ID="main"$' "${OS_RELEASE}"
    grep -q '^PRETTY_NAME="Laptop OS (44.20260907.1)"$' "${OS_RELEASE}"
    grep -q '^VARIANT="Laptop OS"$' "${OS_RELEASE}"
    grep -q '^NAME="laptop-os"$' "${OS_RELEASE}"
    grep -q '^VERSION="44.20260907.1"$' "${OS_RELEASE}"
    grep -q '^IMAGE_ID="laptop-os"$' "${OS_RELEASE}"
    grep -q '^IMAGE_VERSION="44.20260907.1"$' "${OS_RELEASE}"
    # Left alone deliberately: ID is what the BIB manifest lookup and the
    # EFI shim path depend on.
    grep -q '^DEFAULT_HOSTNAME="fedora"$' "${OS_RELEASE}"
    grep -q '^ID=fedora$' "${OS_RELEASE}"
    grep -q '^ID_LIKE="fedora"$' "${OS_RELEASE}"
    # VERSION_ID is the base image's, and is never rewritten: a repeat run
    # must agree with the first.
    grep -q '^VERSION_ID=44$' "${OS_RELEASE}"
}

@test "00-image-info: derives GitHub URLs from image identity" {
    run_script
    [ "$status" -eq 0 ]

    grep -q '^HOME_URL="https://github.com/InvisCo/laptop-os"$' "${OS_RELEASE}"
    grep -q '^DOCUMENTATION_URL="https://github.com/InvisCo/laptop-os/blob/main/README.md"$' "${OS_RELEASE}"
    grep -q '^SUPPORT_URL="https://github.com/InvisCo/laptop-os/issues"$' "${OS_RELEASE}"
    grep -q '^BUG_REPORT_URL="https://github.com/InvisCo/laptop-os/issues/new"$' "${OS_RELEASE}"
    grep -q '^ID_LIKE="fedora"$' "${OS_RELEASE}"
}

@test "00-image-info: permits explicit URL overrides without changing base identity" {
    export HOME_URL="https://laptop-os.example"
    export DOCUMENTATION_URL="https://docs.laptop-os.example"
    export SUPPORT_URL="https://support.laptop-os.example"
    export BUG_REPORT_URL="https://bugs.laptop-os.example"
    run_script
    [ "$status" -eq 0 ]

    grep -q '^PRETTY_NAME="Laptop OS (stable)"$' "${OS_RELEASE}"
    grep -q '^NAME="laptop-os"$' "${OS_RELEASE}"
    grep -q '^ID_LIKE="fedora"$' "${OS_RELEASE}"
    grep -q '^HOME_URL="https://laptop-os.example"$' "${OS_RELEASE}"
    grep -q '^DOCUMENTATION_URL="https://docs.laptop-os.example"$' "${OS_RELEASE}"
    grep -q '^SUPPORT_URL="https://support.laptop-os.example"$' "${OS_RELEASE}"
    grep -q '^BUG_REPORT_URL="https://bugs.laptop-os.example"$' "${OS_RELEASE}"
}

@test "00-image-info: does not write BUILD_ID from a supplied revision" {
    # The build commit is published as org.opencontainers.image.revision, not
    # in os-release: SHA_HEAD_SHORT is declared late in the Containerfile to
    # protect layer caching, so this early phase never sees it.
    export SHA_HEAD_SHORT="abc1234"
    run_script
    [ "$status" -eq 0 ]

    run grep -c '^BUILD_ID=' "${OS_RELEASE}"
    [ "$output" -eq 0 ]
}

@test "00-image-info: is idempotent" {
    run_script
    [ "$status" -eq 0 ]
    run_script
    [ "$status" -eq 0 ]

    run grep -c '^VARIANT_ID=' "${OS_RELEASE}"
    [ "$output" -eq 1 ]
    run grep -c '^IMAGE_ID=' "${OS_RELEASE}"
    [ "$output" -eq 1 ]
}

@test "00-image-info: still writes metadata without os-release" {
    rm -f "${OS_RELEASE}"
    run_script
    [ "$status" -eq 0 ]
    [ -f "${IMAGE_INFO_JSON}" ]
    [ ! -f "${OS_RELEASE}" ]
}

@test "00-image-info: escapes JSON values" {
    export IMAGE_PRETTY_NAME='Finpilot "OS"'
    export IMAGE_NAME='finpilot"test'
    run_script
    [ "$status" -eq 0 ]

    run python3 -m json.tool "${IMAGE_INFO_JSON}"
    [ "$status" -eq 0 ]
    [ "$(json_field image-name)" = 'finpilot"test' ]
}

@test "00-image-info: fails before writing when required identity is missing" {
    unset IMAGE_NAME
    run_script
    [ "$status" -ne 0 ]
    [ ! -f "${IMAGE_INFO_JSON}" ]
}

@test "00-image-info: derives the Fedora major from the base os-release" {
    # This image is based on a Bluefin tag, whose version is Bluefin's build
    # number and not Fedora's major, so the Containerfile has to declare the
    # major separately. The base image's own os-release is the authority: it is
    # the one value that cannot go stale.
    unset FEDORA_MAJOR_VERSION
    run_script
    [ "$status" -eq 0 ]
    [ "$(json_field fedora-version)" = "44" ]
}

@test "00-image-info: fails when the declared Fedora major contradicts the base image" {
    # This is the bug the whole check exists for. A literal in the Containerfile
    # and the base image under it are two sites that can disagree, and quietly
    # preferring either one ships an image that misidentifies its own platform
    # to every consumer of image-info.json.
    export FEDORA_MAJOR_VERSION="43"
    run_script
    [ "$status" -ne 0 ]
    [ ! -f "${IMAGE_INFO_JSON}" ]
    [[ "$output" == *"43"* ]]
    [[ "$output" == *"44"* ]]
}

@test "00-image-info: fails when neither an override nor the base os-release provides the Fedora major" {
    unset FEDORA_MAJOR_VERSION
    rm -f "${OS_RELEASE}"
    run_script
    [ "$status" -ne 0 ]
    [ ! -f "${IMAGE_INFO_JSON}" ]
}

@test "00-image-info: replaces an existing key whose value contains sed metacharacters" {
    # & and the delimiter are metacharacters in a sed replacement, and a URL with
    # a query string is an ordinary value here.
    export HOME_URL="https://laptop-os.example/?a=1&b=2|c"
    run_script
    [ "$status" -eq 0 ]

    grep -qF 'HOME_URL="https://laptop-os.example/?a=1&b=2|c"' "${OS_RELEASE}"
}

@test "00-image-info: appends an absent key verbatim" {
    # A key the base os-release does not carry is added, and must land as data.
    export HOME_URL="https://laptop-os.example/?a=1&b=2|c"
    sed -i '/^HOME_URL=/d' "${OS_RELEASE}"
    run_script
    [ "$status" -eq 0 ]

    grep -qF 'HOME_URL="https://laptop-os.example/?a=1&b=2|c"' "${OS_RELEASE}"
    run grep -c '^HOME_URL=' "${OS_RELEASE}"
    [ "$output" -eq 1 ]
}
