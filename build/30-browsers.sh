#!/usr/bin/env bash

# Exit on error, unset variable, or pipe failure
set -euo pipefail

###############################################################################
# Native browsers: Brave Origin (RPM, adblock built in, no rewards/crypto/VPN)
# and LibreWolf (RPM from the official signed repository). Firefox is
# intentionally NOT shipped; LibreWolf is the primary.
###############################################################################

### Brave Origin from official repository
echo "Installing Brave Origin..."

cat >/etc/yum.repos.d/brave-browser.repo <<'EOF'
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF

dnf5 install -y brave-origin

rm -f /etc/yum.repos.d/brave-browser.repo

echo "Brave Origin installed successfully"

### LibreWolf from official signed repository
echo "Installing LibreWolf..."

cat >/etc/yum.repos.d/librewolf.repo <<'EOF'
[librewolf]
name=LibreWolf Software Repository
baseurl=https://repo.librewolf.net
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://repo.librewolf.net/pubkey.gpg
enabled=1
EOF

dnf5 install -y librewolf

rm -f /etc/yum.repos.d/librewolf.repo

echo "LibreWolf installed successfully"

### Managed policies (password manager offloading)
echo "Installing browser policies..."

# Brave Origin: already debloated upstream (no rewards/crypto wallet/VPN/Tor).
# The policy turns off sync and the built-in password manager (1Password is
# the password manager) and force-installs the 1Password extension.
mkdir -p /etc/brave/policies/managed
install -m 0644 /ctx/overrides/brave/laptop-os.json \
    /etc/brave/policies/managed/laptop-os.json

# LibreWolf: ship the documented per-user overrides file to a stable location;
# a ujust recipe copies it into ~/.librewolf on first use.
mkdir -p /usr/share/laptop-os/librewolf
install -m 0644 /ctx/overrides/librewolf/librewolf.overrides.cfg \
    /usr/share/laptop-os/librewolf/librewolf.overrides.cfg

# Verify the .desktop IDs the dock defaults expect. A renamed .desktop file
# silently vanishes from the dock, so fail loudly here instead.
for desktop_id in librewolf brave-origin; do
    if ! ls /usr/share/applications/"${desktop_id}".desktop >/dev/null 2>&1; then
        echo "WARNING: expected /usr/share/applications/${desktop_id}.desktop not found."
        echo "Installed browser .desktop files:"
        for f in /usr/share/applications/*brave* /usr/share/applications/*librewolf* /usr/share/applications/*wolf*; do
            [[ -e "$f" ]] && basename "$f"
        done
        echo "If the RPM renamed its .desktop file, update"
        echo "overrides/cosmic/com.system76.CosmicAppList/v1/favorites"
    fi
done

echo "Browsers configured successfully"
