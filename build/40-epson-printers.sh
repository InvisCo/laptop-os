#!/usr/bin/env bash

# Exit on error, unset variable, or pipe failure
set -euo pipefail

###############################################################################
# Epson inkjet printer drivers (vendored, no repo carries L355/M105).
#   epson-inkjet-printer-201207w-1.0.1-1.x86_64  (L355)
#   epson-inkjet-printer-201215w-1.0.1-1.x86_64  (M105)
# escpr 1.8.8 (L4160/L3250) is built in Containerfile escpr-builder stage
# from rpms/epson-inkjet-printer-escpr-1.8.8-1.src.rpm and COPY --from
# that stage, so toolchain does not bloat the final image.
# Source for escpr: https://github.com/vmartins/epson-inkjet-printer-escpr
# (GPL-2.0, Seiko Epson; 1.8.8, no active version tracking per owner)
###############################################################################

echo "Installing vendored Epson printer drivers..."

# Integrity is guaranteed by rpms/SHA256SUMS (verified in CI), so the
# legacy vendor signatures (SHA1-era digests) are skipped here.
for rpm in /ctx/rpms/epson-inkjet-printer-*.x86_64.rpm; do
    [ -e "$rpm" ] || continue
    echo "Installing $(basename "$rpm")"
    rpm -Uvh --nodigest --nosignature "$rpm"
done

echo "Epson drivers installed successfully"
