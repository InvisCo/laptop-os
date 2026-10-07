# Build Scripts

This directory contains build scripts used during image creation. The default Containerfile explicitly runs the required scripts; extra scripts must be explicitly added to the Containerfile.

## How It Works

Scripts are named with a number prefix (e.g., `10-build.sh`, `30-browsers.sh`) and run in ascending order during the container build process. A number can be vacated — gaps are fine.

## Included Scripts

- **`10-build.sh`** - Main build script for base system modifications, package installation, and service configuration
- **`30-browsers.sh`** - Brave Origin (adblock built in, no rewards/crypto/VPN — no de-bloat policies needed upstream) + LibreWolf, managed policies from `overrides/`
- **`40-epson-printers.sh`** - Vendored Epson drivers from `rpms/` (legacy signatures, `--nodigest --nosignature`)
- **`50-cosmic-desktop.sh`** - COSMIC desktop swap (the pattern this repo used to ship as an example; it is active here)
- **`clean-stage.sh`** - Build-artifact cleanup before `bootc container lint`

## Adding a Script

This repo ships no `.example` scripts — every script it carries is active, and
the active scripts are the reference: `30-browsers.sh` for the third-party RPM
repository pattern (enable repo → `dnf5 install -y` → remove the repo file),
`50-cosmic-desktop.sh` for a desktop swap.

To add a script: create `NN-name.sh`, then add the standard `RUN` block below
after the `10-build.sh` block in `Containerfile`, replacing `NN-name.sh` with
your script's path.

```dockerfile
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/NN-name.sh
```

Removing a script is the reverse: delete the `RUN` block and the file. The
number it vacated stays vacated — gaps are fine.

## Creating Your Own Scripts

Create numbered scripts for different purposes:

```bash
# 10-build.sh - Base system (already exists)
# 20-drivers.sh - Hardware drivers
# 30-development.sh - Development tools
# 40-gaming.sh - Gaming software
# 50-cleanup.sh - Final cleanup tasks
```

### Script Template

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Running custom setup..."
# Your commands here
```

### Best Practices

- **Use descriptive names**: `30-browsers.sh` is better than `30-stuff.sh`
- **One purpose per script**: Easier to debug and maintain
- **Clean up after yourself**: Remove temporary files and disable temporary repos
- **Test incrementally**: Add one script at a time and test builds
- **Comment your code**: Future you will thank present you

### Disabling Scripts

To disable a script, remove its `RUN` block from `Containerfile`. Keep the file
if you plan to re-activate it, delete it otherwise.

## Execution Order

The template runs scripts explicitly, rather than automatically discovering files by prefix. Place extra script blocks after `10-build.sh` and before `clean-stage.sh`. Use numbered names to communicate the intended order.

## Notes

- Scripts run as root during build
- Build context is available at `/ctx`
- Use dnf5 for package management (not dnf or yum)
- Always use `-y` flag for non-interactive installs
