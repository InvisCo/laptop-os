# GUI applications delivered as Linux Homebrew casks from ublue-os/tap and
# homebrew/cask.
# Installed by: ujust install-apps
#
# Cask postflight steps need root (setgid BrowserSupport/op, setuid
# chrome-sandbox, polkit policy, groupadd), so this Brewfile is deliberately
# separate from default.Brewfile: run it from a terminal, never headless.
#
# Cask tokens from third-party taps are fully qualified. `brew bundle` resolves
# tokens while it loads the file, before its own tap lines run, so a bare tap
# name resolves against homebrew/cask and is skipped as a macOS cask on the
# first run. Core casks use their bare names.
tap "ublue-os/tap", trusted: true
cask "ublue-os/tap/1password-gui-linux"
cask "ublue-os/tap/1password-cli-linux"
# zed is homebrew/cask core; ublue-os/tap removed zed-linux (ublue-os/homebrew-tap#773)
cask "zed"
