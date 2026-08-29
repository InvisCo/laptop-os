###############################################################################
# PROJECT NAME CONFIGURATION
###############################################################################
# Name: laptop-os
#
# IMPORTANT: Change "laptop-os" above to your desired project name.
# This name should be used consistently throughout the repository in:
#   - Justfile: export IMAGE_NAME := env("IMAGE_NAME", "your-name-here")
#   - README.md: # your-name-here (title)
#   - artifacthub-repo.yml: repositoryID: your-name-here
#   - custom/ujust/README.md: localhost/your-name-here:stable (in bootc switch example)
#
# The project name defined here is the single source of truth for your
# custom image's identity. When changing it, update all references above
# to maintain consistency.
###############################################################################

###############################################################################
# MULTI-STAGE BUILD ARCHITECTURE
###############################################################################
# This Containerfile follows the Bluefin architecture pattern as implemented in
# @projectbluefin/distroless. The architecture layers OCI containers together:
#
# 1. Context Stage (ctx) - Combines resources from:
#    - Local build scripts and custom files
#    - @projectbluefin/common - Desktop configuration shared with Aurora
#    - @ublue-os/brew - Homebrew integration
#
# 2. Base Image Options (edit the FROM line below):
#    - `quay.io/fedora-ostree-desktops/silverblue:44` (Fedora 44 and GNOME)
#    - `quay.io/fedora-ostree-desktops/base-main:44` (Fedora 44, no desktop)
#    - `quay.io/centos-bootc/centos-bootc:stream10` (CentOS-based)
#
# See: https://docs.projectbluefin.io/contributing/ for architecture diagram
###############################################################################

# Base Image - GNOME included (Fedora official OSTree desktop)
# Renovate will keep the digest pin up to date.
ARG BASE_IMAGE="quay.io/fedora-ostree-desktops/silverblue:44@sha256:1516b8a2b4e4cbe959c32f8b58abaa9328cd496e2bc3c6c13123dd67794c0f9d"
ARG ESCPR_CFLAGS="-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-implicit-function-declaration"

# OCI context images - imported below and pinned directly in their FROM lines.
# The base image is pinned in the FROM line below and updated by Renovate.
FROM ghcr.io/projectbluefin/common:latest@sha256:44c7c59c910e00a26b0209f8be0915d8c67af095b108ed5a9d4842c32ed63dae AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:e3b6878ed7b5ca963fd3f54ce44e6ab83da7533b28c83b2a11b92a5fedaa4adb AS brew

# Context stage - combine local and imported OCI container resources
FROM scratch AS ctx

COPY build /build
COPY custom /custom
COPY rpms /rpms
COPY overrides /overrides

# Copy from OCI containers to distinct subdirectories to avoid conflicts
COPY --from=common /system_files /oci/common
COPY --from=brew /system_files /oci/brew

# Builder for Epson escpr (L4160/L3250) — keeps gcc/cups-devel out of final image
FROM ${BASE_IMAGE} AS escpr-builder
ARG ESCPR_CFLAGS
COPY --from=ctx /rpms/epson-inkjet-printer-escpr-*.src.rpm /tmp/
RUN dnf5 install -y --setopt=install_weak_deps=0 gcc make autoconf automake libtool cups-devel \
 && mkdir -p /tmp/build /out \
 && rpm2cpio /tmp/epson-inkjet-printer-escpr-*.src.rpm | (cd /tmp/build && cpio -id --quiet) \
 && tar -xzf /tmp/build/epson-inkjet-printer-escpr-*.tar.gz -C /tmp/build \
 && srcdir=$(echo /tmp/build/epson-inkjet-printer-escpr-*/) \
 && (cd "$srcdir" && CFLAGS="${ESCPR_CFLAGS}" ./configure --prefix=/usr --libdir=/usr/lib64 --with-cupsfilterdir=/opt/epson-inkjet-printer-escpr/cups/lib/filter --with-cupsppddir=/opt/epson-inkjet-printer-escpr/ppds/Epson) \
 && make -C "$srcdir" CFLAGS="${ESCPR_CFLAGS}" -j"$(nproc)" \
 && make -C "$srcdir" install-strip DESTDIR=/out \
 && rm -f /out/usr/lib64/*.a /out/usr/lib64/*.la \
 && rm -rf /tmp/build /tmp/*.src.rpm

FROM ${BASE_IMAGE}
# Image identity - these define how bootc, fastfetch, and the ublue ecosystem
# recognize your image. Change these to match your project name.
ARG IMAGE_NAME="laptop-os"
ARG IMAGE_VENDOR="projectbluefin"
ARG UBLUE_IMAGE_TAG="stable"
ARG BASE_IMAGE_NAME="silverblue"
ARG FEDORA_MAJOR_VERSION="44"
ARG VERSION=""

### MODIFICATIONS
## Make modifications desired in your image and install packages by modifying the build scripts.
## The following RUN directives mount the ctx stage which includes:
##   - Local build scripts from /build
##   - Local custom files from /custom
##   - Files from @projectbluefin/common at /oci/common (includes branding/artwork content)
##   - Files from @ublue-os/brew at /oci/brew
## Scripts are run in numerical order (10-build.sh, 20-example.sh, etc.)

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/00-image-info.sh

# Set dnf options before build scripts (persists across subsequent RUN layers)
RUN dnf5 config-manager setopt keepcache=1 install_weak_deps=0

# laptop-os ships RPMs that unpack into a real /opt (1Password, Brave).
# The base image symlinks /opt -> /var/opt which breaks rpm cpio unpacking,
# so swap in a real directory before any build script runs. Unlike the
# template default, this stays a real directory for the life of the image.
RUN rm -f /opt && mkdir -p /opt

# Epson escpr (L4160/L3250) built in escpr-builder; copy without toolchain
COPY --from=escpr-builder /out/opt/epson-inkjet-printer-escpr /opt/epson-inkjet-printer-escpr
COPY --from=escpr-builder /out/usr/lib64/libescpr.so* /usr/lib64/
RUN ldconfig

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/10-build.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/20-onepassword.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/30-browsers.sh

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/40-epson-printers.sh

### CLEANUP
## Use Bluefin's clean-stage.sh to remove build artifacts before linting.
## /run is deliberately not mounted as tmpfs here: clean-stage.sh must remove
## image-layer files such as /run/dnf so bootc lint's nonempty-run-tmp check
## passes. The script tolerates busy Buildah bind mounts while clearing contents.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    /ctx/build/clean-stage.sh

### /opt
## laptop-os keeps /opt as a real directory (see early RUN above) because
## 1Password and Brave install into it. Do NOT replace it with the
## template's `ln -s /var/opt /opt` symlink.

### INIT
## Required for bootc images
CMD ["/sbin/init"]

### LINTING
## Verify final image and contents are correct. --fatal-warnings catches issues.
RUN bootc container lint --fatal-warnings
