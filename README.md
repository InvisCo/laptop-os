# laptop-os

Personal bootc image for a Dell XPS 9315 (Intel i5-1230U/Iris Xe), built from [projectbluefin/finpilot](https://github.com/projectbluefin/finpilot) — the same multi-stage architecture upstream Bluefin/Aurora use (Silverblue 44 base + `@projectbluefin/common`).

Goal: Bluefin-class atomic updates and rollback with every rpm-ostree layer baked into the image.

Published as `ghcr.io/invisco/laptop-os:{stable,stable-testing,testing}`, keyless-signed via Cosign.

## Customizations vs Base

### Added Packages (Build-time)

- **System packages**: `tmux`, `gum` (template defaults), plus `cups-pdf`, `libvirt`, `qemu-kvm`, `virt-manager` (VM workflows).
- **1Password**: desktop app + CLI (`1password`, `1password-cli`) from the official AgileBits RPM repository, so the app, CLI, and browser extensions share native messaging without any sandbox in between.
- **Browsers (native RPMs only — no Flatpak browsers)**:
  - **LibreWolf** (primary) from the official signed `repo.librewolf.net` repository, with the 1Password native-messaging symlink baked in.
  - **Brave Origin** from the official Brave RPM repository — adblock built in, no Rewards/Wallet/VPN/Tor; built-in password manager off via managed policy, 1Password extension force-installed.
- **Zed editor** via the `cjatherton/zed` COPR (isolated enable, upstream-tracked releases).
- **Epson printer drivers**: vendored RPMs (`epson-inkjet-printer-201207w`/`201215w` for L355/M105 + `epson-inkjet-printer-escpr` 1.8.8 src.rpm for L4160/L3250 via https://github.com/vmartins/epson-inkjet-printer-escpr) under `rpms/` with SHA256 checksums.

### Added Applications (Runtime)

- **GUI Apps (Flatpak, first boot)**: 14 apps — Zen browser (casual secondary browser), Betterbird, Apostrophe, GIMP, Inkscape, LibreOffice, Okular, OnlyOffice, ProtonVPN, QPWGraph, RawTherapee, Remmina, RustDesk.

### Removed/Disabled

- No Firefox RPM or Flatpak browser baked in; LibreWolf replaces Firefox, profiles migrate at deploy time.
- Brave Origin ships without crypto wallet/rewards/VPN (no de-bloat needed); sync and the built-in password manager are turned off via `/etc/brave/policies/managed/laptop-os.json`.
- Google Safe Browsing stays off (LibreWolf default).

### Configuration Changes

- LibreWolf loosened-defaults overrides shipped to `/usr/share/laptop-os/librewolf/librewolf.overrides.cfg`; activate per user with `ujust laptop-os-librewolf-overrides`. Active prefs: DRM (EME), WebGL, search suggestions, Firefox Sync UI. GSB, RFP, canvas prompts intentionally untouched.
- 1Password native messaging bridged into LibreWolf: `/usr/lib64/mozilla/native-messaging-hosts -> /usr/lib/librewolf/native-messaging-hosts`.
- `libvirtd.socket` + `libvirtd.service` enabled at boot.

_Last updated: 2026-09-15_

## Repository Layout

| Path | Purpose |
|---|---|
| `Containerfile` | Multi-stage build; pins `common`/`brew`/base digests (Renovate bumps) |
| `build/10-build.sh` | Fedora packages (cups-pdf, virt stack) + Zed COPR + services |
| `build/20-onepassword.sh` | 1Password repo + install + sysusers.d |
| `build/30-browsers.sh` | Brave Origin + LibreWolf repos, native-messaging symlink, policies |
| `build/40-epson-printers.sh` | Vendored Epson RPMs (`--nodigest`, legacy signatures) |
| `overrides/brave/laptop-os.json` | Brave managed policies |
| `overrides/librewolf/librewolf.overrides.cfg` | LibreWolf loosened prefs (source of truth) |
| `rpms/` | Vendored Epson drivers + SHA256SUMS |
| `custom/flatpaks/default.preinstall` | First-boot Flatpaks (14 apps) |
| `custom/ujust/custom-system.just` | `ujust` recipes incl. overrides activation |

Deeper guides live in each subdirectory's `README.md`; template architecture doc is [upstream](https://github.com/projectbluefin/finpilot#architecture).

## Build & Release Flow

Two-branch model:

| Branch | Tag | Purpose |
|---|---|---|
| `main` | `:stable-testing` (+`:testing`) | Testing |
| `stable` | `:stable` | Production |

1. Change something locally, run `just build` to smoke-test (~10 min).
2. Push to `main` → CI builds/pushes `:stable-testing`.
3. `promote-main-to-stable.yml` opens a fast-forward PR `main`→`stable` (`--ff-only`, `--merge` fallback for direct hotfixes) — local workflow, the upstream reusable requires an org `maintainers` team; `publish-stable` builds `:stable` whenever the branch lags the last successful build.
4. Merge publishes `:stable`.

Note: pushes made by `GITHUB_TOKEN` don't trigger workflows — the first-ever promotion seeded `stable` directly and needed a manual `workflow_dispatch` build on the stable branch.

Rollback: pick the previous deployment in GRUB (system state only, `/home` untouched).

## Migration Guide (from stock Bluefin)

Run once when first switching this laptop from layered `ublue-os/bluefin:stable` to this image.

### 1. Before switching — back up to external storage

Everything below lives in `/var/home` and survives the switch; the tar is belt-and-braces.

```bash
tar czf /path/to/nas/pre-migration-$(date +%Y%m%d).tar.gz \
  ~/.var/app/org.mozilla.firefox ~/.var/app/dev.zed.Zed \
  ~/.var/app/com.brave.Browser ~/.var/app/org.mozilla.thunderbird_esr \
  ~/.var/app/org.mozilla.Thunderbird ~/.var/app/eu.betterbird.Betterbird \
  ~/.config/1Password ~/.config/op ~/.config/chezmoi
```

### 2. Verify Signature

```bash
cosign verify \
  --certificate-identity-regexp="https://github\.com/InvisCo/laptop-os/\.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/invisco/laptop-os:stable
```

### 3. Switch

```bash
sudo bootc switch --transport registry ghcr.io/invisco/laptop-os:stable && reboot
```

All previous rpm-ostree layers (1Password, virt stack, cups-pdf, Epson LocalPackages) are dropped automatically — everything is baked into the image. The old Bluefin deployments stay bootable from GRUB; do not run `rpm-ostree cleanup -b` while you want that option.

### 4. After first boot — in order

1. Activate LibreWolf overrides:
   ```bash
   ujust laptop-os-librewolf-overrides
   ```
2. Migrate the Firefox profile into LibreWolf:
   ```bash
   mkdir -p ~/.librewolf
   cp -a ~/.var/app/org.mozilla.firefox/.mozilla/firefox/* ~/.librewolf/
   ```
   If the profile does not load, create `~/.librewolf/profiles.ini` pointing `Path=` at the copied profile directory.
3. Launch LibreWolf: verify bookmarks, logins, extensions, and that the 1Password extension unlocks against the desktop app (native messaging symlink is baked).
4. Migrate the Zed config into the image's RPM build, then launch and check settings:
   ```bash
   cp -a ~/.var/app/dev.zed.Zed/config/zed ~/.config/zed
   ```
5. 1Password needs no migration (RPM→RPM, same `~/.config/1Password` path): launch, sign in, `op whoami`.
6. Verify Brave Origin: it ships with 1Password X force-installed. The old Brave Flatpak keeps working in parallel until you migrate its profile.
7. Print a test page on each Epson queue; `virsh list --all` (virt stack check); confirm the Zen Flatpak arrived (`flatpak list | grep -i zen`).
8. Only after everything checks out, remove superseded Flatpaks (no `--delete-data` — data stays in `~/.var/app` and on the NAS):
   ```bash
   flatpak uninstall org.mozilla.firefox dev.zed.Zed org.mozilla.thunderbird_esr org.mozilla.Thunderbird
   ```

Thunderbird account migration to Betterbird is not needed if you keep the Betterbird Flatpak (its own profile is untouched); copy Thunderbird's profile only if you want its accounts inside Betterbird.

### Rollback

Pick the previous Bluefin deployment in GRUB and reboot. `/var/home` is untouched — flatpaks, profiles, keyring, and `/home/linuxbrew` all survive. If the old deployments were ever pruned, `bootc switch --transport registry ghcr.io/ublue-os/bluefin:stable` re-pulls the base image.

## Gotchas (learned here)

- **Real `/opt` required**: base image symlinks `/opt -> /var/opt`, which breaks rpm unpacking of 1Password/Brave Origin. Containerfile converts it to a real directory before build scripts; do not restore the symlink.
- **Epson RPMs are legacy-signed**: need `rpm --nodigest --nosignature`; integrity enforced by `rpms/SHA256SUMS`.
- **bootc lint sysusers check**: RPMs creating groups without sysusers.d fragments fail `--fatal-warnings` (see `20-onepassword.sh`).
- **Build scripts must be executable** — `chmod +x build/*.sh` or CI fails with `Permission denied`.
- **Actions must be allowed to create PRs**: repo setting "Allow GitHub Actions to create and approve pull requests" (API: `actions/permissions/workflow`).
- **Flatpaks install on first boot** via `flatpak-preinstall.service`, not during `bootc switch`; Homebrew likewise via `brew-setup.service`. Wait for both before assuming failure.
