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
  - **Brave** from the official Brave RPM repository, de-bloated via managed policies (Rewards/Wallet/VPN/Tor/AI-chat off, built-in password manager off, 1Password extension force-installed).
- **Zed editor** via the `cjatherton/zed` COPR (isolated enable, upstream-tracked releases).
- **Epson printer drivers**: vendored RPMs (`epson-inkjet-printer-201207w`/`201215w` for L355/M105 + `epson-inkjet-printer-escpr` 1.8.8 src.rpm for L4160/L3250 via https://github.com/vmartins/epson-inkjet-printer-escpr) under `rpms/` with SHA256 checksums.

### Added Applications (Runtime)

- **GUI Apps (Flatpak)**: Zen browser (`app.zen_browser.zen`) as a casual secondary browser.

### Removed/Disabled

- No Firefox RPM or Flatpak browser baked in; LibreWolf replaces Firefox, profiles migrate at deploy time.
- Brave crypto wallet/rewards/VPN/news disabled via `/etc/brave/policies/managed/laptop-os.json`.
- Google Safe Browsing stays off (LibreWolf default); uBlock Origin covers mal-domain blocking.

### Configuration Changes

- LibreWolf loosened-defaults overrides shipped to `/usr/share/laptop-os/librewolf/librewolf.overrides.cfg`; activate per user with `ujust laptop-os-librewolf-overrides`. Active prefs: DRM (EME), WebGL, search suggestions, Firefox Sync UI. GSB, RFP, canvas prompts intentionally untouched.
- 1Password native messaging bridged into LibreWolf: `/usr/lib64/mozilla/native-messaging-hosts -> /usr/lib/librewolf/native-messaging-hosts`.
- `libvirtd.socket` + `libvirtd.service` enabled at boot.

_Last updated: 2026-08-24_

## Repository Layout

| Path | Purpose |
|---|---|
| `Containerfile` | Multi-stage build; pins `common`/`brew`/base digests (Renovate bumps) |
| `build/10-build.sh` | Fedora packages (cups-pdf, virt stack) + Zed COPR + services |
| `build/20-onepassword.sh` | 1Password repo + install + sysusers.d |
| `build/30-browsers.sh` | Brave + LibreWolf repos, native-messaging symlink, policies |
| `build/40-epson-printers.sh` | Vendored Epson RPMs (`--nodigest`, legacy signatures) |
| `overrides/brave/laptop-os.json` | Brave managed policies |
| `overrides/librewolf/librewolf.overrides.cfg` | LibreWolf loosened prefs (source of truth) |
| `rpms/` | Vendored Epson drivers + SHA256SUMS |
| `custom/flatpaks/default.preinstall` | First-boot Flatpaks (Zen) |
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
3. `promote-main-to-stable.yml` opens a squash PR `main`→`stable` (local workflow — the upstream reusable requires an org `maintainers` team). Auto-merge is enabled.
4. Merge publishes `:stable`.

Note: pushes made by `GITHUB_TOKEN` don't trigger workflows — the first-ever promotion seeded `stable` directly and needed a manual `workflow_dispatch` build on the stable branch.

Rollback: pick the previous deployment in GRUB (system state only, `/home` untouched).

## Migration Guide (from stock Bluefin)

Run once when first switching this laptop from layered `ublue-os/bluefin:stable` to this image.

### 1. Before switching — back up profiles

```bash
mkdir -p ~/Repositories/laptop-os-migration-backup
cp -a ~/.var/app/org.mozilla.firefox/.mozilla/firefox ~/Repositories/laptop-os-migration-backup/
cp -a ~/.var/app/org.mozilla.thunderbird_esr/.thunderbird ~/Repositories/laptop-os-migration-backup/ 2>/dev/null || true
```

### 2. Switch

```bash
sudo bootc switch --transport registry ghcr.io/invisco/laptop-os:stable-testing && reboot
```

All previous rpm-ostree layers (1Password, virt stack, cups-pdf, Epson LocalPackages) are dropped automatically — everything is baked into the image. The old Bluefin deployment stays bootable from GRUB.

### 3. After first boot — in order

1. Activate LibreWolf overrides:
   ```bash
   ujust laptop-os-librewolf-overrides
   ```
2. Migrate the Firefox profile into LibreWolf:
   ```bash
   mkdir -p ~/.librewolf
   cp -a ~/.var/app/org.mozilla.firefox/.mozilla/firefox/* ~/.librewolf/
   # if ~/.librewolf/profiles.ini doesn't exist or lacks your profile,
   # create it pointing Path= at the copied profile directory
   ```
3. Launch LibreWolf: verify bookmarks, logins, extensions, and that the 1Password extension unlocks against the desktop app (native messaging symlink is baked).
4. Verify the rest of the triangle: `op whoami`, and Brave's force-installed 1Password extension.
5. Print a test page on each Epson queue; boot a VM in virt-manager; confirm Zen Flatpak arrived (`flatpak list | grep zen`).
6. Only after everything checks out, remove superseded Flatpaks:
   ```bash
   flatpak uninstall --user org.mozilla.firefox dev.zed.Zed org.mozilla.thunderbird_esr
   ```

Thunderbird account migration to Betterbird is not needed if you keep the Betterbird Flatpak (its own profile is untouched); copy Thunderbird's profile only if you want its accounts inside Betterbird.

### 4. Go to production

After stable-testing survives a few days:

```bash
sudo bootc switch --transport registry ghcr.io/invisco/laptop-os:stable && reboot
```

Future updates arrive automatically via staged updates against this image.

## Verify Signature

```bash
cosign verify \
  --certificate-identity-regexp="https://github\.com/InvisCo/laptop-os/\.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/invisco/laptop-os:stable
```

## Gotchas (learned here)

- **Real `/opt` required**: base image symlinks `/opt -> /var/opt`, which breaks rpm unpacking of 1Password/Brave. Containerfile converts it to a real directory before build scripts; do not restore the symlink.
- **Epson RPMs are legacy-signed**: need `rpm --nodigest --nosignature`; integrity enforced by `rpms/SHA256SUMS`.
- **bootc lint sysusers check**: RPMs creating groups without sysusers.d fragments fail `--fatal-warnings` (see `20-onepassword.sh`).
- **Build scripts must be executable** — `chmod +x build/*.sh` or CI fails with `Permission denied`.
- **Actions must be allowed to create PRs**: repo setting "Allow GitHub Actions to create and approve pull requests" (API: `actions/permissions/workflow`).
- **Flatpaks install on first boot** via `flatpak-preinstall.service`, not during `bootc switch`; Homebrew likewise via `brew-setup.service`. Wait for both before assuming failure.
