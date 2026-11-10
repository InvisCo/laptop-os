# laptop-os

Personal bootc image for a Dell XPS 9315 (Intel i5-1230U/Iris Xe), built from [projectbluefin/finpilot](https://github.com/projectbluefin/finpilot) — the same multi-stage architecture upstream Bluefin/Aurora use (Silverblue 44 base + `@projectbluefin/common`).

Goal: Bluefin-class atomic updates and rollback with every rpm-ostree layer baked into the image.

Published as `ghcr.io/invisco/laptop-os:{stable,stable-testing,testing}`, keyless-signed via Cosign.

## Customizations vs Base

### Added Packages (Build-time)

- **System packages**: `tmux`, `gum` (template defaults), plus `cups-pdf`, `libvirt`, `qemu-kvm`, `virt-manager` (VM workflows).
- **1Password**: desktop app + CLI as Linux Homebrew casks (`1password-gui-linux`, `1password-cli-linux`) from `ublue-os/tap`, installed at runtime by `ujust install-apps`. Nothing 1Password-related is baked into the image.
- **Browsers (native RPMs only — no Flatpak browsers)**:
  - **LibreWolf** (primary) from the official signed `repo.librewolf.net` repository.
  - **Brave Origin** from the official Brave RPM repository — adblock built in, no Rewards/Wallet/VPN/Tor; built-in password manager off via managed policy, 1Password extension force-installed.
- **Epson printer drivers**: vendored RPMs (`epson-inkjet-printer-201207w`/`201215w` for L355/M105 + `epson-inkjet-printer-escpr` 1.8.8 src.rpm for L4160/L3250 via https://github.com/vmartins/epson-inkjet-printer-escpr) under `rpms/` with SHA256 checksums.

### Added Applications (Runtime)

- **GUI Apps (Homebrew casks, `ujust install-apps`)**: 1Password desktop app, 1Password CLI, Zed — from `ublue-os/tap`. Requires a terminal (cask postflight uses sudo).
- **GUI Apps (Flatpak, first boot)**: 12 apps — Betterbird, Apostrophe, GIMP, Inkscape, LibreOffice, Okular, OnlyOffice, ProtonVPN, QPWGraph, RawTherapee, Remmina, RustDesk.

### Removed/Disabled

- No Firefox RPM or Flatpak browser baked in; LibreWolf replaces Firefox, profiles migrate at deploy time.
- Brave Origin ships without crypto wallet/rewards/VPN (no de-bloat needed); sync and the built-in password manager are turned off via `/etc/brave/policies/managed/laptop-os.json`.
- Google Safe Browsing stays off (LibreWolf default).

### Configuration Changes

- LibreWolf loosened-defaults overrides shipped to `/usr/share/laptop-os/librewolf/librewolf.overrides.cfg`; activate per user with `ujust laptop-os-librewolf-overrides`. Active prefs: DRM (EME), WebGL, search suggestions, Firefox Sync UI. GSB, RFP, canvas prompts intentionally untouched.
- 1Password browser integration depends on three things that look fine until they are not, all asserted by `ujust install-apps`: the `onepassword` group must have a **GID >= 1000** and must not share one with a dynamic systemd user (the RPM's `groupadd -r` makes a sub-1000 group and collides with `systemd-coredump`/`pipewire`, which `usermod` cannot move); `kernel.yama.ptrace_scope` must be **>= 1** (the helper aborts otherwise); and the calling user must be a **member** of the group, which is fixed at login, so 1Password must be started from a session opened afterwards. The image pins both GIDs in `/usr/lib/sysusers.d/1password.conf` and sets `ptrace_scope=1`, so the package never allocates its own. The helper must be exec'd **directly** — routing it through `sg onepassword -c ...` leaves `AT_SECURE` unset and the helper aborts with "running without libc's security".
- Brave Origin and LibreWolf (both native RPMs) integrate natively. Flatpak browsers need the bridge: `ujust install-1password-bridge`, which writes an in-sandbox wrapper plus manifests to all three directories Gecko scans, and allowlists `flatpak-session-helper`. `flatpak-session-helper` must be in `/etc/1password/custom_allowed_browsers` (kept in `/etc`, so re-run after every `bootc switch`, like `install-apps`).
- `ujust install-apps` re-asserts the permissions 1Password authenticates against — `root:onepassword 2755` on `1Password-BrowserSupport`, `root:onepassword-cli 2755` on `op`, `root:root 4755` on `chrome-sandbox`. The cask applies them through `sudo:` postflight steps, and a declined password prompt leaves them user-owned, which the app reports as "invalid group attempted to connect". The recipe repairs and then asserts, so it fails loudly instead of shipping an app that cannot talk to a browser.
- `libvirtd.socket` + `libvirtd.service` enabled at boot.

_Last updated: 2026-10-06_

## Repository Layout

| Path | Purpose |
|---|---|
| `Containerfile` | Multi-stage build; pins `common`/`brew`/base digests (Renovate bumps) |
| `build/10-build.sh` | Fedora packages (cups-pdf, virt stack) + services |
| `build/30-browsers.sh` | Brave Origin + LibreWolf repos, managed policies |
| `build/40-epson-printers.sh` | Vendored Epson RPMs (`--nodigest`, legacy signatures) |
| `overrides/brave/laptop-os.json` | Brave managed policies |
| `overrides/librewolf/librewolf.overrides.cfg` | LibreWolf loosened prefs (source of truth) |
| `rpms/` | Vendored Epson drivers + SHA256SUMS |
| `custom/flatpaks/default.preinstall` | First-boot Flatpaks (13 apps, incl. LibreWolf) |
| `custom/brew/apps.Brewfile` | 1Password app/CLI + Zed as Linux casks |
| `custom/ujust/custom-apps.just` | `ujust install-apps` + Brewfile shortcuts |
| `custom/ujust/custom-system.just` | `ujust` recipes incl. overrides activation |

Deeper guides live in each subdirectory's `README.md`; template architecture doc is [upstream](https://github.com/projectbluefin/finpilot#architecture).

## Build & Release Flow

Two-branch model:

| Branch | Tag | Purpose |
|---|---|---|
| `main` | `:stable-testing` (+`:testing`) | Testing |
| `stable` | `:stable` (promoted digest, never rebuilt) | Production |

1. Change something locally, run `just build` to smoke-test (~10 min).
2. Push to `main` → CI builds and signs the candidate, pushing `:stable-testing` and `:testing`.
3. `promote-main-to-stable.yml` opens a squash PR `main`→`stable` daily — a thin caller for the upstream `reusable-promote-squash.yml`, with `request_reviewer: false` because a personal account has no org `maintainers` team. Merge it **from the UI**: a merge performed as `github-actions` creates no workflow runs, so the release would never fire.
4. `execute-release.yml` verifies the signed `:testing` candidate's cosign signature and copies that exact digest to `:stable`. Nothing rebuilds on `stable`, so the production image is byte-for-byte what was tested on `main`. A failed signature check rejects the candidate and leaves the previous `:stable` in place.

Squash is required, not cosmetic: `execute-release.yml` recognises a promotion by its commit subject, and a fast-forward merge lands no new commit on `stable`, so the release is refused.

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

Note what this is and is not. The signature exists and this command checks it,
but **the installed image does not verify it on update**: the update transport
in `image-info.json` is `ostree-unverified-image:`, and that is deliberate.
A `ostree-image-signed:` transport would first consult
`/etc/containers/policy.json`, whose sigstore scopes cover only
`ghcr.io/ublue-os` and `quay.io/toolbx-images` — this image's namespace falls
through to the `""` catch-all (`insecureAcceptAnything`), so it would report
success without checking anything. Signing a scope for it does not help either:
the image is signed keyless, and containers/image matches a Fulcio certificate
on `subjectEmail` alone, which a GitHub Actions certificate has no value for.
Enforcing this on device would need key-based signing. Verify it at deploy time,
as above, and treat the running image as trusted-by-acquisition.

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
3. Install the cask apps and wire native messaging:
   ```bash
   ujust install-apps
   ```
   It prints `Repairing …` for the setuid/setgid bits the cask's sudo postflight
   may not have applied, creates the `onepassword` groups with pinned GIDs, adds
   your user to them, and ends with a `FAIL:` line if any part did not land.
   **Log out and back in afterwards** — group membership is fixed at login, so
   1Password must be started from a session opened after this. For a Flatpak
   browser also run `ujust install-1password-bridge`.
   Confirm integration from the app log after toggling the browser on:
   ```bash
   grep -iE 'verified successfully|invalid group' ~/.config/1Password/logs/1Password_rCURRENT.log | tail
   ```
4. Launch LibreWolf (native RPM): verify bookmarks, logins, extensions, and that the 1Password extension unlocks against the desktop app. Only a Flatpak browser needs `ujust install-1password-bridge`.
5. Migrate the Zed config from the Flatpak to the cask build, then launch and check settings (the cask `zed` is on `PATH` via Homebrew, config path unchanged):
   ```bash
   cp -a ~/.var/app/dev.zed.Zed/config/zed ~/.config/zed
   ```
6. 1Password stores its vault config at `~/.config/1Password` regardless of packaging: launch, sign in, `op whoami`.
7. Verify Brave Origin: it ships with 1Password X force-installed. The old Brave Flatpak keeps working in parallel until you migrate its profile.
8. Print a test page on each Epson queue; `virsh list --all` (virt stack check).
9. Only after everything checks out, remove superseded Flatpaks (no `--delete-data` — data stays in `~/.var/app` and on the NAS):
   ```bash
   flatpak uninstall org.mozilla.firefox dev.zed.Zed org.mozilla.thunderbird_esr org.mozilla.Thunderbird
   ```

Thunderbird account migration to Betterbird is not needed if you keep the Betterbird Flatpak (its own profile is untouched); copy Thunderbird's profile only if you want its accounts inside Betterbird.

### Rollback

Pick the previous Bluefin deployment in GRUB and reboot. `/var/home` is untouched — flatpaks, profiles, keyring, and `/home/linuxbrew` all survive. If the old deployments were ever pruned, `bootc switch --transport registry ghcr.io/ublue-os/bluefin:stable` re-pulls the base image.

## Gotchas (learned here)

- **Real `/opt` required**: base image symlinks `/opt -> /var/opt`, which breaks rpm unpacking of Brave Origin and the vendored Epson drivers. Containerfile converts it to a real directory before build scripts; do not restore the symlink.
- **Epson RPMs are legacy-signed**: need `rpm --nodigest --nosignature`; integrity enforced by `rpms/SHA256SUMS`.
- **bootc lint sysusers check**: RPMs creating groups without sysusers.d fragments fail `--fatal-warnings`. Nothing in this image creates groups at build time any more (1Password moved to Homebrew casks, which `groupadd` at runtime into mutable `/etc`).
- **Homebrew casks need a terminal**: `apps.Brewfile` postflight steps run `sudo` (setgid `op`/`1Password-BrowserSupport`, setuid `chrome-sandbox`, polkit policy, `groupadd`). Never install it from a headless service, and trust the tap first — the `trusted: true` flag on the `tap` line does that inside `brew bundle`.
- **`bootc switch` resets `/etc`**: the `onepassword*` groups and `/etc/1password/custom_allowed_browsers` that the casks create live in `/etc`, so a switch to a new image drops them. Homebrew itself lives in `/home` and survives. Re-run `ujust install-apps` after every switch.
- **Build scripts must be executable** — `chmod +x build/*.sh` or CI fails with `Permission denied`.
- **Actions must be allowed to create PRs**: repo setting "Allow GitHub Actions to create and approve pull requests" (API: `actions/permissions/workflow`).
- **Flatpaks install on first boot** via `flatpak-preinstall.service`, not during `bootc switch`; Homebrew likewise via `brew-setup.service`. Wait for both before assuming failure.
