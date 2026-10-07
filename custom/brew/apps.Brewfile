# GUI applications delivered as Linux Homebrew casks from ublue-os/tap.
# Installed by: ujust install-apps
#
# Cask postflight steps need root (setgid BrowserSupport/op, setuid
# chrome-sandbox, polkit policy, groupadd), so this Brewfile is deliberately
# separate from default.Brewfile: run it from a terminal, never headless.
#
# Cask tokens are fully qualified. `brew bundle` resolves tokens while it
# loads the file, before its own tap lines run, so a bare name resolves
# against homebrew/cask and is skipped as a macOS cask on the first run.
tap "ublue-os/tap", trusted: true
cask "ublue-os/tap/1password-gui-linux"
cask "ublue-os/tap/1password-cli-linux"
cask "ublue-os/tap/zed-linux"
