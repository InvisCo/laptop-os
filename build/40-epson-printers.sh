#!/usr/bin/env bash

# Exit on error, unset variable, or pipe failure
set -euo pipefail

###############################################################################
# Epson inkjet printer drivers (proprietary, vendored from Epson).
# These were previously installed as rpm-ostree LocalPackages on the source
# system; they must be vendored because no repository carries them.
# NEVRA must match exactly what was layered:
#   epson-inkjet-printer-201207w-1.0.1-1.x86_64
#   epson-inkjet-printer-201215w-1.0.1-1.x86_64
###############################################################################

echo "Installing vendored Epson printer drivers..."

# Integrity is guaranteed by rpms/SHA256SUMS (verified in CI), so the
# legacy vendor signatures (SHA1-era digests) are skipped here.
for rpm in /ctx/rpms/epson-inkjet-printer-*.rpm; do
    echo "Installing $(basename "$rpm")"
    rpm -Uvh --nodigest --nosignature "$rpm"
done

echo "Epson drivers installed successfully"
