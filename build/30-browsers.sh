#!/usr/bin/env bash

# Exit on error, unset variable, or pipe failure
set -euo pipefail

###############################################################################
# Native browsers: Brave (RPM, de-bloated via managed policies) and LibreWolf
# (RPM from the official signed repository, with 1Password native-messaging
# bridge). Firefox is intentionally NOT shipped; LibreWolf is the primary.
###############################################################################

### Brave Browser from official repository
echo "Installing Brave..."

cat >/etc/yum.repos.d/brave-browser.repo <<'EOF'
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/x86_64/
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
EOF

dnf5 install -y brave-browser

rm -f /etc/yum.repos.d/brave-browser.repo

echo "Brave installed successfully"

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

### 1Password <-> browser native messaging bridges
# 1Password ships its Firefox-family native messaging manifest into
# /usr/lib64/mozilla/native-messaging-hosts. LibreWolf only looks in its own
# directory, so link them per upstream FAQ:
# https://librewolf.net/docs/faq/#how-do-i-get-native-messaging-to-work
echo "Wiring 1Password native messaging into LibreWolf..."
mkdir -p /usr/lib/librewolf
ln -sfn /usr/lib64/mozilla/native-messaging-hosts /usr/lib/librewolf/native-messaging-hosts

### Managed policies (de-bloat + password manager offloading)
echo "Installing browser policies..."

# Brave: managed enterprise policies
mkdir -p /etc/brave/policies/managed
install -m 0644 /ctx/overrides/brave/laptop-os.json \
    /etc/brave/policies/managed/laptop-os.json

# LibreWolf: ship the documented per-user overrides file to a stable location;
# a ujust recipe copies it into ~/.librewolf on first use.
mkdir -p /usr/share/laptop-os/librewolf
install -m 0644 /ctx/overrides/librewolf/librewolf.overrides.cfg \
    /usr/share/laptop-os/librewolf/librewolf.overrides.cfg

echo "Browsers configured successfully"
