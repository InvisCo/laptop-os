---
name: finpilot-custom
description: >-
  Runtime layer of finpilot: Brewfiles, Flatpaks, and ujust commands — syntax,
  placement, and validation. Use when modifying custom/ or explaining the
  runtime layer to contributors.
---

# finpilot Runtime Layer

## When to Use

- Adding or editing Homebrew Brewfiles (`custom/brew/*.Brewfile`)
- Adding or editing Flatpak preinstall files (`custom/flatpaks/*.preinstall`)
- Adding or editing ujust command files (`custom/ujust/*.just`)
- Explaining the runtime vs build-time distinction to contributors
- Debugging why a Brewfile or Flatpak didn't install as expected

## When NOT to Use

- Build script changes — use `finpilot-build`
- CI workflow changes — use `finpilot-ci`
- Adding system packages at build-time — use `finpilot-packages`

## Core Process

1. **Identify the runtime need**: CLI tool, GUI app, or user convenience command
2. **Choose the right runtime file**: Brewfile (CLI), Flatpak (GUI), or ujust (shortcut)
3. **Apply correct syntax** for each file type
4. **Validate locally** before opening a PR

## Brewfiles: `custom/brew/*.Brewfile`

Brewfiles use Ruby syntax. They define Homebrew packages installed by users after deployment. Homebrew itself is pre-staged at build time via the `@ublue-os/brew` OCI container and extracted on first boot by `brew-setup.service`; Brewfiles define what users install after that extraction.

### File Locations

| File                               | Purpose                                 |
| ---------------------------------- | --------------------------------------- |
| `custom/brew/default.Brewfile`     | General purpose CLI tools               |
| `custom/brew/development.Brewfile` | Development tools and environments      |
| `custom/brew/fonts.Brewfile`       | Font packages                           |
| `custom/brew/apps.Brewfile`        | GUI casks from `ublue-os/tap`           |
| Custom `*.Brewfile`                | Create as needed for specific use cases |

### Syntax

```ruby
# CLI tools
brew "bat"        # Better cat with syntax highlighting
brew "eza"        # Modern replacement for ls
brew "ripgrep"    # Faster grep
brew "fd"         # Simple alternative to find

# Taps (repositories)
tap "homebrew/cask"

# Casks (work on Linux; GUI apps from ublue-os/tap, tokens fully qualified)
tap "ublue-os/tap", trusted: true
cask "ublue-os/tap/1password-gui-linux"
cask "ublue-os/tap/zed-linux"
```

### Linux Casks

Homebrew casks run on Linux. `ublue-os/tap` ships Linux builds
(`1password-gui-linux`, `1password-cli-linux`, `zed-linux`,
`visual-studio-code-linux`, ...). Four constraints:

1. **Trust the tap.** Third-party taps are untrusted by default. Declare
   `tap "ublue-os/tap", trusted: true` — `brew bundle` trusts it, and
   `build/validate-brewfiles.sh` accepts that literal form (it rejects computed
   tap lines, which is the point).
2. **Qualify the tokens.** Write `cask "ublue-os/tap/zed-linux"`, never
   `cask "zed-linux"`. `brew bundle` resolves tokens while loading the file,
   before its own tap lines run, so a bare name resolves against
   `homebrew/cask`, gets skipped as "requires macOS", and the first run installs
   nothing. Running `brew trust ublue-os/tap` + `brew tap ublue-os/tap` before
   `brew bundle` is the belt.
3. **Interactive sudo.** Casks with `postflight_steps` that touch `/etc`,
   `groupadd`, or setuid/setgid bits run `sudo`. Ship them in their own Brewfile
   (`apps.Brewfile`) behind a ujust recipe; never wire them into a systemd unit.
   Declining the prompt silently leaves the payload user-owned, so the recipe
   must re-assert the contract and fail loudly — for 1Password that is
   `root:onepassword 2755` on `1Password-BrowserSupport`, `root:onepassword-cli
   2755` on `op`, `root:root 4755` on `chrome-sandbox`. See
   `tests/template/install-apps_test.bats` for the assert pattern.
4. **Mutable `/etc` output.** Groups and `/etc/1password/custom_allowed_browsers`
   created by casks are reset by `bootc switch` (Homebrew itself lives in
   `/home` and survives). Document "re-run the recipe after every switch".

Keep casks out of `default.Brewfile` — that file must stay headless-installable.

### 1Password browser integration: what actually breaks it

Both native browsers (Brave Origin, LibreWolf RPM) and Flatpak browsers can work.
The integration fails for reasons that have nothing to do with packaging, so
check these three before touching permissions again:

1. **The integration group needs a GID >= 1000, and no other account may share
   it.** The RPM's `groupadd -r` makes a *system* group, which lands below
   `GID_MIN` (963 on a stock image) and collides with the dynamic systemd users
   `systemd-coredump` and `pipewire` — which `usermod` cannot move, because
   nss-systemd synthesises them and they have no `/etc/passwd` entry. Symptom:
   `invalid group attempted to connect` on every attempt while the file contract
   looks perfect (`root:onepassword 2755`, correct app group). Upstream match:
   `lizalc/gentoo-lizalc#1`, which reproduces it on any distro with a
   sub-1000 `onepassword` gid. Pin the GIDs in the image
   (`/usr/lib/sysusers.d/1password.conf`, written by `build/10-build.sh`) so the
   package finds them present, and have `install-apps` assert/repair via
   `ensure_group`. The app also validates the peer's group against **its own**
   supplementary groups, so the user must be a member — and membership is fixed
   at login, so 1Password must be started from a session opened after that.
2. **`kernel.yama.ptrace_scope` must be >= 1.** With 0 the helper logs "Yama is
   absent or ptrace_scope is set to 0" and aborts before it ever connects.
   Bluefin ships 0; the image sets 1 in `/usr/lib/sysctl.d/90-1password.conf`.
3. **Exec the helper directly — never `sg onepassword -c ...`.** `sg` execs the
   helper from a shell that *already* holds the group, so there is no privilege
   transition: `AT_SECURE` stays 0 and the helper aborts with "process detected
   it was running without libc's security". Forcing the gid with `sg` therefore
   makes things worse, not better. Let the setgid bit do the work.

What is *not* a cause, despite looking like one: Chromium's `NO_NEW_PRIVS`. The
renderer/gpu children carry `NoNewPrivs: 1`, but the native messaging host is
spawned with `nnp=0` and Brave Origin connects natively with no bridge at all.

Both browsers are native RPMs and integrate directly; no Flatpak browser is
preinstalled, and LibreWolf deliberately is not (it would duplicate the RPM).
For a Flatpak browser add the bridge (`ujust install-1password-bridge [HELPER]
[FLATPAK_ID]` in `custom/ujust/custom-apps.just`, defaulting to
`io.gitlab.librewolf-community`): the app stays native, and an
in-sandbox wrapper calls `flatpak-spawn --host <helper>`. Two gotchas: Gecko
reads manifests from three places (user-level dir, XDG config dir, **and** the
profile dir) — writing one produces a browser that silently never spawns the
host; and `flatpak-session-helper` must be in
`/etc/1password/custom_allowed_browsers`.

Three justfile constraints, all learned the hard way:

1. **No heredocs.** just cannot parse `<<EOF` blocks. Assemble generated files
   with `printf '%s\n'` lines.
2. **Backslash-escape literal dollars.** `$$` passes through to the shell
   untouched (bash then eats it as PID). Write `\$@` in single quotes and
   `\"…\${…}…\"` in double quotes — see the wrapper writer.
3. **Keep recipe functions awk-extractable.** `tests/template/bridge_test.bats`
   and `tests/template/install-apps_test.bats` extract `bridge_helper`,
   `bridge_manifest_dirs`, `bridge_write` and `ensure_group` verbatim and drive
   them with shims; the extractor stops at the 4-space-indented `}`, so no other
   column-4 lone brace may appear inside those functions.

Note `getent` exits non-zero for a missing group: under `set -e -o pipefail` an
unguarded `have="$(getent ...)"` aborts the recipe before it can create it.

### How Users Invoke Them

Users install via `ujust` commands (shortcuts defined in `custom/ujust/*.just`):

```bash
# Install GUI casks (interactive sudo)
ujust install-apps

# Install default apps
ujust install-default-apps

# Install dev tools
ujust install-dev-tools

# Install fonts
ujust install-fonts
```

### Validation

- **PR trigger**: `validate-brewfiles.yml` runs on PRs that touch `custom/brew/**`
- **Local check**: `brew bundle check --file /path/to/Brewfile`
- **List what would install**: `brew bundle list --file /path/to/Brewfile`

## Flatpaks: `custom/flatpaks/*.preinstall`

Flatpak preinstall files use INI format. They define GUI apps installed after first boot.

### File Locations

| File                                 | Purpose                                |
| ------------------------------------ | -------------------------------------- |
| `custom/flatpaks/default.preinstall` | Default GUI applications               |
| Custom `*.preinstall`                | Create as needed for specific app sets |

### Syntax

```ini
[Flatpak Preinstall org.mozilla.firefox]
Branch=stable

[Flatpak Preinstall com.visualstudio.code]
Branch=stable

[Flatpak Preinstall org.gnome.Calculator]
Branch=stable
```

### Key Rules

- **Post-first-boot only**: Flatpaks are NOT baked into the ISO or container. They install on first boot with internet access — do not rely on them in offline scenarios or ISO-based installs without network.
- **Always specify `Branch=stable`** (or another valid branch)
- **Find app IDs at https://flathub.org/**
- **Validation**: `validate-flatpaks.yml` checks that app IDs exist on Flathub

## ujust: `custom/ujust/*.just`

ujust files define user convenience commands. All `.just` files are auto-consolidated during the build.

### Critical Rule: NEVER USE `dnf5` IN JUST FILES

ujust commands are shortcuts for user convenience — they should only invoke Brewfiles, Flatpaks, or other user-level tools. **Never use `dnf5` or any package manager in a just file.**

### Common Structure

```just
# vim: set ft=make :

[group('Apps')]
install-default-apps:
    #!/usr/bin/env bash
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile

[group('Apps')]
install-dev-tools:
    #!/usr/bin/env bash
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile

[group('System')]
my-custom-command:
    #!/usr/bin/env bash
    echo "Running custom command..."
    # Your logic here (NO dnf5!)
```

### Syntax Rules

- Use `#!/usr/bin/env bash` shebang for bash blocks
- Use `[group('Category')]` for organization in `ujust --list`
- All `.just` files are merged into `/usr/share/ublue-os/just/60-custom.just`
- Use descriptive, kebab-case command names

### Validation

- **PR trigger**: `validate-justfiles.yml` runs on PRs that touch `Justfile` or `custom/ujust/*.just`
- **Local check**: `just --list`
- **Syntax validation**: `just --unstable --fmt --check -f custom/ujust/your-file.just`

## Desktop UI defaults: `overrides/`

`overrides/` holds files copied into the image verbatim by a `build/*.sh` step.
Two shapes exist: managed-policy/config files for a specific app (`brave/`,
`librewolf/`) and the desktop's own default config.

### COSMIC dock favorites

Desktop is COSMIC, so there is no dconf and no `favorite-apps`. cosmic-config
stores one RON value per file, keyed by component and version:

```
overrides/cosmic/com.system76.CosmicAppList/v1/favorites   # Vec<String> of desktop IDs
```

`build/50-cosmic-desktop.sh` installs it to
`/usr/share/cosmic/com.system76.CosmicAppList/v1/favorites`. cosmic-config falls
back to that path (`XDG_DATA_DIRS`, prefix `cosmic`) on a per-key basis, so it
only supplies values for users who have not pinned apps themselves.

Rules:

- **Install it in `50-cosmic-desktop.sh`, not `10-build.sh`.** The cosmic
  packages ship their own default schema under `/usr/share/cosmic`.
- **IDs are stored without `.desktop`.** cosmic's `get_app_id` strips it.
- **An unmatched ID does not vanish** — it renders as a broken placeholder icon.
  Verify IDs at build time (`30-browsers.sh` for browsers, `50-*.sh` for COSMIC
  apps) rather than assuming a typo is harmless.
- **`ujust set-dock-layout` copies the image file** over the user's
  `~/.config/cosmic/...`. One source of truth; the applet watches the user
  directory, so a plain write reloads live.

## Validation Workflows by File Type

| File Type      | Validation Workflow      | What It Checks              |
| -------------- | ------------------------ | --------------------------- |
| `*.Brewfile`   | `validate-brewfiles.yml` | Syntax, package existence   |
| `*.preinstall` | `validate-flatpaks.yml`  | App ID existence on Flathub |
| `*.just`       | `validate-justfiles.yml` | `just --list` syntax check  |

## Common Rationalizations

| Rationalization                                                             | Reality                                                                                               |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| "I'll add `dnf5 install` to a just file for convenience."                   | **Never.** ujust is for user-level shortcuts. Use `build/10-build.sh` for system packages.            |
| "Flatpaks should be in the container so they work offline."                 | Flatpaks are intentionally post-first-boot to keep the container small and allow independent updates. |
| "I'll put the Brewfile inline in the just file instead of a separate file." | Separate Brewfiles are easier to validate and let users install them manually too.                    |
| "The just file doesn't need a shebang if it's just one command."            | Always use a shebang (`#!/usr/bin/env bash`) for explicit execution context.                          |

## Red Flags

- `dnf5` or `rpm-ostree` in any `.just` file
- Flatpak preinstall missing `Branch=stable`
- Brewfile without a corresponding `ujust` shortcut in `custom/ujust/`
- App ID in `.preinstall` not verified on Flathub
- Just file using `dnf` or `yum` instead of proper Brewfile/Flatpak shortcuts

## Verification

- [ ] Does each `.Brewfile` have a corresponding `ujust` shortcut?
- [ ] Do all Flatpak entries specify `Branch=stable`?
- [ ] Are all app IDs in `.preinstall` files verified on Flathub?
- [ ] Does `just --list` pass without errors?
- [ ] Does `brew bundle check --file` pass for each Brewfile?
- [ ] Is there NO `dnf5`, `dnf`, or `rpm-ostree` in any `.just` file?
