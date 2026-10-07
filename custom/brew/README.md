# Homebrew Integration

This directory contains Brewfile declarations that will be copied into your custom image at `/usr/share/ublue-os/homebrew/`.

## What are Brewfiles?

Brewfiles are Homebrew's way of declaring packages in a declarative format. They allow you to specify which packages, taps, and casks you want installed.

## How It Works

1. **During Build**: Files in this directory are copied to `/usr/share/ublue-os/homebrew/` in the image
2. **After Installation**: Users install packages by running `brew bundle` commands
3. **User Experience**: Declarative package management via Homebrew

## Usage

### Adding Brewfiles to Your Image

1. Create `.Brewfile` files in this directory
2. Add your desired packages using Brewfile syntax
3. Build your image - the Brewfiles will be copied to `/usr/share/ublue-os/homebrew/`

**Example Files in this directory:**
- [`default.Brewfile`](default.Brewfile) - Essential command-line tools
- [`development.Brewfile`](development.Brewfile) - Development tools and languages
- [`fonts.Brewfile`](fonts.Brewfile) - Programming fonts
- [`apps.Brewfile`](apps.Brewfile) - GUI casks from `ublue-os/tap` (1Password app/CLI, Zed)

### Linux casks

Homebrew casks work on Linux, and [ublue-os/tap](https://github.com/ublue-os/homebrew-tap)
ships Linux builds of GUI apps (`1password-gui-linux`, `1password-cli-linux`,
`zed-linux`, `visual-studio-code-linux`, ...). Two constraints:

1. Third-party taps must be trusted before Homebrew will run their code. Declare
   it as `tap "ublue-os/tap", trusted: true` — `brew bundle` trusts it, and
   `build/validate-brewfiles.sh` accepts that literal form.
2. Cask postflight steps that touch `/etc`, `groupadd`, or setuid/setgid bits run
   `sudo`. Install those Brewfiles interactively (`ujust install-apps`), never
   from a systemd unit. The runtime artifacts they create live in `/etc` and are
   reset by `bootc switch`, so re-run the recipe after every switch.

### Installing Packages from Brewfiles

After booting into your custom image, install packages with:

```bash
brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile
```

Or use the convenient ujust commands defined in [`custom/ujust/custom-apps.just`](../ujust/custom-apps.just):
```bash
ujust install-apps
ujust install-default-apps
ujust install-dev-tools
ujust install-fonts
```

## File Format

Brewfiles use Ruby syntax:

```ruby
# Add a tap (third-party repository)
tap "homebrew/cask"

# Install a formula (CLI tool)
brew "bat"
brew "eza"
brew "ripgrep"

# Install a cask (GUI application, macOS only)
cask "visual-studio-code"
```

## Customization

Edit the existing Brewfiles or create new ones:
- **[`default.Brewfile`](default.Brewfile)** - Modify for your essential tools
- **[`development.Brewfile`](development.Brewfile)** - Add your dev stack
- **[`fonts.Brewfile`](fonts.Brewfile)** - Add preferred fonts
- **Create new files** - `gaming.Brewfile`, `media.Brewfile`, etc.

When you add new Brewfiles, create corresponding ujust commands in [`custom/ujust/custom-apps.just`](../ujust/custom-apps.just) for easy installation.

## Resources

- [Homebrew Documentation](https://docs.brew.sh/)
- [Brewfile Documentation](https://github.com/Homebrew/homebrew-bundle)
- [Bluefin Homebrew Guide](https://docs.projectbluefin.io/administration#homebrew)
