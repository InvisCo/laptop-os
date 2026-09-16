#!/usr/bin/env bash

# Exit on error, unset variable, or pipe failure
set -euo pipefail

###############################################################################
# 1Password desktop app + CLI from the official AgileBits RPM repository
###############################################################################

echo "Installing 1Password..."

# Add 1Password RPM repository GPG key
rpm --import https://downloads.1password.com/linux/keys/1password.asc

# Add 1Password RPM repository
cat >/etc/yum.repos.d/1password.repo <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

# Install desktop app + CLI
dnf5 install -y 1password 1password-cli

# bootc lint: declare the RPM-created groups via sysusers.d
cat >/usr/lib/sysusers.d/laptop-os-1password.conf <<'EOF'
# Groups shipped by the 1Password RPMs (bootc lint sysusers check)
g onepassword -
g onepassword-cli -
g onepassword-mcp -
EOF

# Trust LibreWolf for browser integration. 1Password only talks to allowlisted
# browser binaries; forks like LibreWolf need an entry in
# /etc/1password/custom_allowed_browsers (root-owned, per 1Password docs
# "Connect additional browsers to the 1Password app").
mkdir -p /etc/1password
echo "librewolf" >/etc/1password/custom_allowed_browsers
chown root:root /etc/1password/custom_allowed_browsers
chmod 0644 /etc/1password/custom_allowed_browsers

# Clean up repo file (required - repos don't work at runtime in bootc images)
rm -f /etc/yum.repos.d/1password.repo

echo "1Password installed successfully"
