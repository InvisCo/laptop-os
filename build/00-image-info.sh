#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Image Info Generation
###############################################################################
# Generates /usr/share/ublue-os/image-info.json and customizes /usr/lib/os-release.
# This script is bluefin-pattern: each consumer provides its own branding.
#
# Required env vars (set as ARGs in Containerfile):
#   IMAGE_NAME          - Image name (e.g. finpilot, my-custom-os)
#   IMAGE_PRETTY_NAME   - Human-readable name (e.g. Laptop OS) for GRUB/PRETTY_NAME
#   IMAGE_VENDOR        - Image vendor/owner (e.g. github username or org)
#   UBLUE_IMAGE_TAG     - Image tag/stream (e.g. stable, testing, latest)
#   BASE_IMAGE_NAME     - Base image name (e.g. bluefin). Supplied by `just build`,
#                         derived from the Containerfile's base FROM line
#   FEDORA_MAJOR_VERSION - Fedora version (e.g. 44). Declared in the
#                         Containerfile and verified against the base image's
#                         own /usr/lib/os-release below
#   VERSION             - Full version string (e.g. stable-42.20250531)
#   SHA_HEAD_SHORT      - Short git SHA (optional, for dev builds)
###############################################################################

# The Containerfile is the source of truth for IMAGE_NAME, IMAGE_VENDOR and
# UBLUE_IMAGE_TAG. BASE_IMAGE_NAME describes the base image, whose FROM line is
# its source of truth; `just build` derives it from there and passes it in.
: "${IMAGE_NAME:?IMAGE_NAME must be set}"
: "${IMAGE_VENDOR:?IMAGE_VENDOR must be set}"
: "${UBLUE_IMAGE_TAG:?UBLUE_IMAGE_TAG must be set}"
: "${BASE_IMAGE_NAME:?BASE_IMAGE_NAME must be set}"

# Paths. ROOT_DIR is a test seam: it is empty in the Containerfile build, where
# these resolve to the image root, and set to a scratch tree by the BATS suite.
ROOT_DIR="${ROOT_DIR:-}"
IMAGE_INFO="${ROOT_DIR}/usr/share/ublue-os/image-info.json"
OS_RELEASE="${ROOT_DIR}/usr/lib/os-release"

# The base image owns the Fedora major, but its tag cannot supply one here: this
# image is based on a Bluefin tag, whose version is Bluefin's build number
# rather than Fedora's major. So the Containerfile declares
# FEDORA_MAJOR_VERSION and `just build` passes it through. Verify it against the
# base image we actually built on: a stale literal would otherwise ship an image
# that misidentifies its own platform to every consumer of image-info.json.
# VERSION_ID is never rewritten below, so a repeat run agrees.
if [[ -r "${OS_RELEASE}" ]]; then
	base_fedora_major="$(sed -n 's/^VERSION_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "${OS_RELEASE}")"
	if [[ -n "${base_fedora_major}" && "${base_fedora_major}" != "${FEDORA_MAJOR_VERSION:-}" ]]; then
		echo "ERROR: Containerfile declares FEDORA_MAJOR_VERSION=${FEDORA_MAJOR_VERSION} but the base image is Fedora ${base_fedora_major}" >&2
		echo "       Update the ARG; the base image changed under a literal." >&2
		exit 1
	fi
fi

# Branding — customize these for your image
IMAGE_PRETTY_NAME="${IMAGE_PRETTY_NAME:-Laptop OS}"
IMAGE_LIKE="${IMAGE_LIKE:-fedora}"
HOME_URL="${HOME_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}}"
DOCUMENTATION_URL="${DOCUMENTATION_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/blob/main/README.md}"
SUPPORT_URL="${SUPPORT_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/issues}"
BUG_REPORT_URL="${BUG_REPORT_URL:-https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/issues/new}"

# Derive image flavor from name
if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
	IMAGE_FLAVOR="nvidia"
else
	IMAGE_FLAVOR="main"
fi

# Image ref (used by bootc for upgrade source)
IMAGE_REF="ostree-image-signed:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"

###############################################################################
# Write image-info.json
###############################################################################
mkdir -p /usr/share/ublue-os
cat >"${IMAGE_INFO}" <<EOF
{
  "image-name": "${IMAGE_NAME}",
  "image-flavor": "${IMAGE_FLAVOR}",
  "image-vendor": "${IMAGE_VENDOR}",
  "image-ref": "${IMAGE_REF}",
  "image-tag": "${UBLUE_IMAGE_TAG}",
  "base-image-name": "${BASE_IMAGE_NAME}",
  "fedora-version": "${FEDORA_MAJOR_VERSION}"
}
EOF

echo "Wrote ${IMAGE_INFO}"
echo "  image-name: ${IMAGE_NAME}"
echo "  image-flavor: ${IMAGE_FLAVOR}"
echo "  image-vendor: ${IMAGE_VENDOR}"

###############################################################################
# Customize /usr/lib/os-release
###############################################################################
# Bluefin pattern: sed-replace the keys the base image ships so kernel-install
# (20-grub.install mkbls: title from NAME + VERSION) picks up our branding.
# Appending duplicate keys does NOT work — first occurrence wins. ID stays
# fedora (BIB manifest lookup + EFIDIR shim path depend on it); ID_LIKE marks
# the lineage. GRUB titles on already-deployed systems refresh on the next
# kernel reinstall via `bootc upgrade`.
if [[ -f "${OS_RELEASE}" ]]; then
	# Read existing values
	if [[ -n "${VERSION:-}" ]]; then
		OS_VERSION="${VERSION}"
	else
		OS_VERSION="${UBLUE_IMAGE_TAG}"
	fi

	set_key() {
		local key="$1" value="$2"
		if grep -q "^${key}=" "${OS_RELEASE}"; then
			sed -i "s|^${key}=.*|${key}=\"${value}\"|" "${OS_RELEASE}"
		else
			echo "${key}=\"${value}\"" >>"${OS_RELEASE}"
		fi
	}

	set_key "NAME" "${IMAGE_NAME}"
	set_key "PRETTY_NAME" "${IMAGE_PRETTY_NAME} (${OS_VERSION})"
	set_key "VARIANT" "${IMAGE_PRETTY_NAME}"
	set_key "VARIANT_ID" "${IMAGE_FLAVOR}"
	set_key "VERSION" "${OS_VERSION}"
	set_key "IMAGE_ID" "${IMAGE_NAME}"
	set_key "IMAGE_VERSION" "${OS_VERSION}"
	set_key "ID_LIKE" "${IMAGE_LIKE}"
	set_key "HOME_URL" "${HOME_URL}"
	set_key "DOCUMENTATION_URL" "${DOCUMENTATION_URL}"
	set_key "SUPPORT_URL" "${SUPPORT_URL}"
	set_key "BUG_REPORT_URL" "${BUG_REPORT_URL}"

	echo "Rebranded ${OS_RELEASE} as ${IMAGE_PRETTY_NAME}"
fi
