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

# The base image's own os-release is authoritative for the Fedora major. It is
# also the only source that cannot go stale: the Containerfile declares
# FEDORA_MAJOR_VERSION only because this image is based on a Bluefin tag, whose
# version is Bluefin's build number rather than Fedora's major, so the major has
# to be written down somewhere. `just build` passes that declaration through.
#
# Use the base image's value when there is one, and treat a disagreement as a
# hard error rather than silently preferring either side. Two sites that
# disagree is the failure this whole check exists to catch: the image would
# otherwise report a platform it was not built on, to every consumer of
# image-info.json. VERSION_ID is never rewritten below, so a repeat run agrees.
base_fedora_major=""
if [[ -r "${OS_RELEASE}" ]]; then
	base_fedora_major="$(sed -n 's/^VERSION_ID="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "${OS_RELEASE}")"
fi
if [[ -n "${base_fedora_major}" ]]; then
	if [[ -n "${FEDORA_MAJOR_VERSION:-}" && "${base_fedora_major}" != "${FEDORA_MAJOR_VERSION}" ]]; then
		echo "ERROR: Containerfile declares FEDORA_MAJOR_VERSION=${FEDORA_MAJOR_VERSION}" >&2
		echo "       but the base image is Fedora ${base_fedora_major}." >&2
		echo "       Update the ARG; the base image changed under a literal." >&2
		exit 1
	fi
	FEDORA_MAJOR_VERSION="${base_fedora_major}"
fi
: "${FEDORA_MAJOR_VERSION:?FEDORA_MAJOR_VERSION must be set or derivable from ${OS_RELEASE}}"

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

# Image ref (used by bootc for the upgrade source).
#
# Deliberately an *unverified* transport: nothing on an installed system can
# check this image's signature, so claiming otherwise would be decorative.
# `ostree-image-signed:` means "verify against /etc/containers/policy.json
# first", and that policy arrives from Bluefin's shared overlay, whose sigstore
# scopes cover ghcr.io/ublue-os and quay.io/toolbx-images. This namespace falls
# through to the `""` catch-all (insecureAcceptAnything), so a signed transport
# would report success without checking anything.
#
# Adding a scope would not fix it either, because the image is signed keyless:
# the identity lives in a URI SAN
# (https://github.com/${IMAGE_VENDOR}/${IMAGE_NAME}/.github/workflows/...), and
# containers/image matches a Fulcio certificate on `subjectEmail` alone —
# mandatory, exact, with an explicit FIXME for URI SANs in
# signature/fulcio_cert.go. A GitHub Actions certificate carries no email SAN,
# so no policy entry can match one. Device-side enforcement needs key-based
# signing; a code-signing key in a published container image is not a
# possibility, because pulling the image requires reading the key.
#
# Keeping `docker://` matters: `just _build-bib` recovers the published
# reference from this field for the ISO, stripping everything up to it. A
# registry-shorthand transport has no docker:// to strip and the ISO would be
# built against a reference still carrying the transport prefix.
IMAGE_REF="ostree-unverified-image:docker://ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"

###############################################################################
# Write image-info.json
###############################################################################
# JSON-escape every interpolated value. These are build ARGs, so they are
# under the repository's control, but a quote in a name or pretty-name yields a
# file no parser accepts — and the consumers are `bootc switch`, the ujust
# recipes and the ISO build, so the failure surfaces far from the cause.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "${s}"
}

mkdir -p "$(dirname "${IMAGE_INFO}")"
cat >"${IMAGE_INFO}" <<EOF
{
  "image-name": "$(json_escape "${IMAGE_NAME}")",
  "image-flavor": "$(json_escape "${IMAGE_FLAVOR}")",
  "image-vendor": "$(json_escape "${IMAGE_VENDOR}")",
  "image-ref": "$(json_escape "${IMAGE_REF}")",
  "image-tag": "$(json_escape "${UBLUE_IMAGE_TAG}")",
  "base-image-name": "$(json_escape "${BASE_IMAGE_NAME}")",
  "fedora-version": "$(json_escape "${FEDORA_MAJOR_VERSION}")"
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

	# Replace via awk, not sed: the value is user-facing text (a URL with a
	# query string, a version with a dot) and `&`, `\` and the delimiter are
	# metacharacters in a sed replacement. awk treats the value as data.
	#
	# Appending is not an option on its own: the first occurrence of a key wins
	# in os-release, so a duplicate would leave the base image's value in
	# effect. The existing line is removed first.
	set_key() {
		local key="$1" value="$2" tmp
		tmp="$(mktemp)"
		awk -v k="${key}" -v v="${value}" '
			$0 ~ "^" k "=" { print k "=\"" v "\""; next }
			{ print }
		' "${OS_RELEASE}" >"${tmp}"
		if ! grep -q "^${key}=" "${OS_RELEASE}"; then
			printf '%s="%s"\n' "${key}" "${value}" >>"${tmp}"
		fi
		cat "${tmp}" >"${OS_RELEASE}"
		rm -f "${tmp}"
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
