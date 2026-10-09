---
name: finpilot-troubleshooting
description: >-
  Consolidated symptom-cause-fix table for finpilot. Covers local build failures,
  CI failures, runtime issues, Renovate problems, COPR persistence, and ujust
  command not found. Use when something is broken and you need a quick diagnosis.
---

# finpilot Troubleshooting

## When to Use

- A local build fails and you need to diagnose the cause
- CI is failing on a PR and the error is unclear
- A runtime issue appears after deployment (missing packages, failed services)
- Renovate is not creating PRs or is failing
- A COPR repo seems to persist across builds
- A `ujust` command is not found or not working

## When NOT to Use

- You are still setting up the fork for the first time — use `finpilot-onboarding`
- You are deciding where to add a package — use `finpilot-packages`
- You need to plan ongoing maintenance — use `finpilot-maintain`

## Core Process

1. **Identify the symptom** from the tables below
2. **Check the likely cause**
3. **Apply the solution**
4. **Verify the fix**

## Local Build Failures

| Symptom                                | Cause                                                            | Solution                                                                         |
| -------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Build fails: "permission denied"       | Signing misconfigured or `id-token: write` permission missing    | Verify `id-token: write` and `attestations: write` are granted in the workflow   |
| Build fails: "package not found"       | Typo in package name, or package unavailable in configured repos | Check spelling, verify on RPMfusion, add COPR if needed                          |
| Build fails: "base image not found"    | Invalid `FROM` line or digest mismatch                           | Check Containerfile syntax, verify base image tag and digest                     |
| Build fails: "shellcheck error"        | Script syntax error in `build/*.sh`                              | Run `shellcheck build/*.sh` locally, fix errors                                  |
| `bootc container lint` fails           | Missing cleanup, leftover artifacts, or invalid image structure  | Run `build/clean-stage.sh` manually, check for stray files in `/opt` or `/var`   |
| Podman/Docker not found                | Container runtime not installed                                  | Install `podman` or `docker`, ensure daemon is running                           |
| Base image pull fails                  | Network issue or invalid digest                                  | Verify network, check digest is correct, try `podman pull <base-image>` manually |
| Multi-stage build fails at `ctx` stage | Missing `COPY --from=` or invalid OCI image reference            | Verify OCI image names and digests in `Containerfile` ctx stage                  |
| `just build` fails immediately         | `just` not installed or `Justfile` syntax error                  | Run `just --list`, check `Justfile` for syntax errors                            |

## CI Failures

| Symptom                                                                 | Cause                                                                                                                                       | Solution                                                                                                                  |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| PR validation fails: shellcheck                                         | Syntax error in modified `.sh` file                                                                                                         | Run `shellcheck build/*.sh` locally, fix errors                                                                           |
| PR validation fails: hadolint                                           | Dockerfile lint rule violation                                                                                                              | Check `.hadolint.yaml` for allowed suppressions, fix or document new ones                                                 |
| PR validation fails: Brewfile                                           | Invalid Brewfile syntax                                                                                                                     | Check Ruby syntax, ensure packages exist (`brew search`)                                                                  |
| PR validation fails: Flatpak                                            | Invalid app ID                                                                                                                              | Verify app ID exists on https://flathub.org/                                                                              |
| PR validation fails: justfile                                           | Invalid just syntax                                                                                                                         | Run `just --list` locally to test, fix syntax                                                                             |
| CI build fails: workflow permissions                                    | Missing `id-token: write` or `packages: write`                                                                                              | Verify `.github/workflows/build-image.yml` has correct permissions                                                        |
| CI build fails: token health                                            | `RENOVATE_TOKEN` or `GITHUB_TOKEN` invalid/expired                                                                                          | Check token expiry, verify scopes, regenerate if needed                                                                   |
| CI build fails: signing misconfig                                       | OIDC token unavailable (self-hosted runner or restricted permissions)                                                                       | Verify `id-token: write` is granted and the runner supports OIDC; signing is `continue-on-error`, so builds still publish |
| CI build fails: composite action not found                              | Wrong commit SHA or repo name in `uses:`                                                                                                    | Verify `projectbluefin/actions` SHA, check network access                                                                 |
| CI build succeeds but image not published                               | Wrong `IMAGE_NAME` or `IMAGE_VENDOR`                                                                                                        | Check `Containerfile` ARGs, verify `clean.yml` package name matches                                                       |
| Promotion gate blocked: `release/blocked`, cosign "no signatures found" | Image pushed by an older template snapshot before signing was default, or the `Sign and publish` step failed silently (`continue-on-error`) | Merge a new build on `main` so a signed `:testing` image is published; check the build log's sign step for errors         |
| Push to `stable` fires no Actions runs | GitHub push-event blackout on the branch (observed Aug 30 - Sep 14 2026; self-resolved). Under digest promotion this means `:stable` silently goes stale | Check `gh api repos/OWNER/REPO/actions/runs?branch=stable`; promote the current candidate with `gh workflow run execute-release.yml --repo OWNER/REPO` |
| Promotion merged but `:stable` image not updated | `execute-release.yml` refused the push, or never ran. It requires the merge to have produced a `chore: promote ...` subject, so a fast-forward or bot-authored merge is refused by design | Read the failed run's log. Merge the promotion PR from the UI as a human, or `gh workflow run execute-release.yml --repo OWNER/REPO` after inspecting the candidate |
| GHCR push fails: `uploading layer chunked: StatusCode: 400 <html>` | Transient registry gateway error mid-upload | Rerun the failed build (`gh run rerun <id>` or `gh workflow run`); if it persists, check GHCR status and file upstream |

## Runtime Issues

| Symptom                                 | Cause                                                       | Solution                                                                                                                        |
| --------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Flatpaks not installed                  | Expected behavior — they install post-first-boot            | Ensure internet connection on first boot, or run `ujust install-default-apps`                                                   |
| Brew missing or not found               | Homebrew not extracted yet or service failed | Run `systemctl status brew-setup.service`. Homebrew is extracted on first boot via systemd service, not user-installed. Check `/var/home/linuxbrew/.linuxbrew/bin/brew` |
| `bootc switch` fails                    | Wrong image URL or missing registry credentials             | Verify bootc switch URL matches your repo (see `iso/iso.toml`), check registry access                                           |
| `bootc switch` fails: "image not found" | Image not yet published to GHCR                             | Trigger a build on `main`, verify image appears under Packages                                                                  |
| Service not starting                    | Service not enabled or missing dependency                   | Check `systemctl status service.name`, verify `systemctl enable` in `build/10-build.sh`                                         |
| Missing package after boot              | Installed in wrong layer or runtime vs build-time confusion | Check if it's in `build/10-build.sh` (build-time) or `custom/brew/` (runtime)                                                   |
| `/opt` is not writable                  | `/opt` is symlinked to `/var/opt` by default                | In `Containerfile`, replace `RUN rm -rf /opt && ln -s /var/opt /opt` with `RUN rm /opt && mkdir /opt` if immutability is needed |

## Renovate Issues

| Symptom                       | Cause                                              | Solution                                                                   |
| ----------------------------- | -------------------------------------------------- | -------------------------------------------------------------------------- |
| Renovate not creating PRs     | `RENOVATE_TOKEN` missing, expired, or wrong scopes | Verify token is Classic PAT with `repo` + `workflow`, regenerate if needed |
| Renovate PRs fail CI          | Renovate branch is out of date with `main`         | Rebase Renovate branch, or close and let Renovate recreate                 |
| Renovate updates wrong files  | Misconfigured `renovate.json`                      | Run `renovate-config-validator .github/renovate.json`, fix regex patterns  |
| Renovate creates too many PRs | Broad match in `renovate.json`                     | Scope `matchPackageNames` or `matchPaths` more narrowly                    |
| Renovate workflow times out   | Large number of repositories or heavy load         | Check Renovate logs, increase timeout, or run manually                     |

## COPR Persistence Issues

| Symptom                                 | Cause                                                         | Solution                                                                                      |
| --------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| COPR packages missing after boot        | COPR not disabled correctly, repo persists but packages don't | Use `copr_install_isolated` from `build/copr-helpers.sh` — it enables, installs, and disables |
| COPR conflicts on update                | Multiple COPRs enabled simultaneously                         | Ensure all COPRs are disabled after install, use isolated installs only                       |
| `dnf5 copr list` shows unexpected repos | Old COPR not cleaned up                                       | Remove repo files from `/etc/yum.repos.d/` if not managed by `copr_install_isolated`          |

## Homebrew Cask Issues

| Symptom                                                       | Cause                                                            | Solution                                                                                                                                   |
| ------------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `brew bundle` refuses the tap / untrusted tap warning         | Third-party taps are untrusted by default since Homebrew 4.5     | Declare `tap "ublue-os/tap", trusted: true` in the Brewfile, or run `brew trust ublue-os/tap`                                              |
| "Skipping cask … (requires macOS)", nothing installs on first run | `brew bundle` resolves bare cask tokens at load time, before its tap lines, so they hit `homebrew/cask` | Qualify the token: `cask "ublue-os/tap/zed-linux"`; run `brew trust` + `brew tap` before bundling                          |
| Cask install fails in a systemd unit / non-interactive shell | Cask `postflight_steps` need `sudo` (setuid/setgid, `groupadd`, `/etc`) | Install the cask Brewfile from a terminal (`ujust install-apps`); keep it out of `default.Brewfile`                                       |
| 1Password says "invalid group attempted to connect" | Helper is not `root:onepassword 2755`, **or** the file contract holds but the `onepassword` group has a GID below `GID_MIN` (or shares one with a dynamic systemd user) | `ujust install-apps` asserts both. Confirm: `getent group onepassword` (gid >= 1000), `id -nG` (contains `onepassword`), `cat /proc/sys/kernel/yama/ptrace_scope` (>= 1) |
| 1Password helper logs "Yama is absent or ptrace_scope is set to 0" | `kernel.yama.ptrace_scope` is 0 | `sudo sysctl -w kernel.yama.ptrace_scope=1`; laptop-os sets it in the image |
| 1Password helper logs "running without libc's security, aborting" | Helper was exec'd from a shell that already held the group (`sg onepassword -c ...`), so `AT_SECURE` never got set | Exec the setgid helper **directly**; never wrap it in `sg` |
| Flatpak browser never spawns the native host, no error anywhere | Manifest written to one directory only; Gecko reads the user-level dir, the XDG config dir, **and** the profile dir | `ujust install-1password-bridge` writes all three |
| Extension talks to the helper but gets `AppQuit` from the native core | Helper cannot reach the app (peer rejected downstream of a working manifest) | Check the app log triple (`invalid group` + `Extension connecting` + `NoCreds`); move the browser into a Flatpak and wire the bridge rather than re-asserting file modes |
| Browser extension cannot reach the 1Password app              | Manifest points at a removed path, or the browser scans its own directory | Re-run `ujust install-apps`; LibreWolf needs `~/.librewolf/native-messaging-hosts`, Brave Origin needs `Brave-Origin/NativeMessagingHosts` |
| 1Password refuses a forked browser                            | Browser binary not in `/etc/1password/custom_allowed_browsers`    | Append the binary name (`librewolf`), then restart the app                                                                                 |
| `mv EPERM` on a native messaging manifest                    | Manifest locked with `chattr +i` by an external bridge            | Casks detect the lock and skip it; `sudo chattr -i <manifest>` to hand control back to Homebrew                                            |
| Groups/allowlist gone after `bootc switch`                    | `onepassword*` groups and `/etc/1password` are mutable `/etc` state | Re-run `ujust install-apps` after every switch; Homebrew in `/home` survives                                                               |

## ujust Command Not Found

| Symptom                                | Cause                                                           | Solution                                                                             |
| -------------------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `ujust` not found                      | `ujust` not in PATH, or shell not reloaded                      | Open a new terminal, or source shell profile (`source ~/.bashrc`)                    |
| `ujust --list` missing custom commands | `.just` files not copied during build                           | Verify `custom/ujust/*.just` files exist and are copied in `build/10-build.sh`       |
| `ujust my-command` fails               | Script error in `.just` file                                    | Run `just --list` to check syntax, or run the script block manually for error output |
| `ujust install-default-apps` fails     | Brew not installed or Brewfile path wrong                       | Verify brew is installed, check `BREWFILE` path in the just command                  |
| ujust on ISO vs installed system       | ujust commands may differ between live ISO and installed system | Ensure commands are designed for the target environment (ISO vs installed)           |

## Common Rationalizations

| Rationalization                                                   | Reality                                                                                                                                              |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| "The build failed in CI but works locally — it must be a CI bug." | CI is the source of truth. Local environments often have cached layers or different podman versions. Start with `just build` on a clean environment. |
| "Renovate is broken — it hasn't made a PR in days."               | Renovate runs on a schedule (default 6h). Check the workflow run logs before assuming failure.                                                       |
| "I don't need to run shellcheck locally — CI will catch it."      | Running `shellcheck` locally is faster and keeps CI queues free. It's a 5-second check.                                                              |
| "The COPR was disabled, so it can't be the problem."              | Repo files can persist in `/etc/yum.repos.d/` even if `copr` metadata is gone. Check the directory directly.                                         |

## Red Flags

- Skipping local `just build` before opening a PR
- Ignoring CI failures because "it worked on my machine"
- Manually updating digests in `Containerfile` instead of using Renovate
- Leaving COPRs enabled after install
- Not verifying app IDs on Flathub before adding to `.preinstall`
- Pushing fixes directly to `main` instead of opening a PR

## Verification

- [ ] Did you identify the correct category (local, CI, runtime, Renovate, COPR, ujust)?
- [ ] Did you check the symptom-cause table for your specific error?
- [ ] Did you apply the recommended solution?
- [ ] Did you verify the fix by running the relevant test (build, just --list, etc.)?
- [ ] If the issue persists, did you check the workflow logs or run with verbose output (`--log-level=debug`)?
