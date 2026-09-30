---
name: finpilot-pr-checklist
description: >-
  PR gates and pre-commit checklist by change type. Covers validation commands
  for Containerfile, build scripts, Brewfiles, Flatpaks, ujust, workflows, and
  README changes. Use before opening or reviewing a PR.
---

# finpilot PR Checklist

## When to Use

- Before opening a new pull request
- Before pushing changes that modify build scripts, CI workflows, or runtime files
- When reviewing a PR and verifying the author ran the correct validation steps
- When setting up pre-commit hooks or CI validation rules

## When NOT to Use

- The PR only contains documentation changes without affecting build/CI — still run markdown lint, but full checklist is overkill
- You are troubleshooting an already-open PR — use `finpilot-troubleshooting`

## Core Process

0. **Check for an existing open PR against the same issue** — before writing any
   code, run `gh pr list --state open --search "<issue-number>"` and skim
   `gh pr list --state open`. Multiple agents work this repo concurrently; if a
   PR already addresses the issue, review or extend it instead of opening a
   competing one. Duplicate PRs get closed and the work is wasted.
1. **Identify which files changed**
2. **Run the relevant validation commands** from the tables below
3. **Fix any errors** before opening the PR
4. **Open the PR** and ensure all status checks pass

## Pre-Commit Checklist (Applies to ALL Commits)

Before every commit, run:

### 1. Conventional Commits

Ensure commit messages follow the format:

```
<type>[optional scope]: <description>
```

Valid types: `feat`, `fix`, `docs`, `chore`, `build`, `ci`, `refactor`, `test`

Examples:

```
feat: add tmux to default build
docs: update README with raptor section
ci: add validate-brewfiles workflow
```

### 2. Shellcheck

Run on all modified shell files:

```bash
shellcheck build/*.sh
```

**Fix ALL errors before committing.** Shellcheck in CI is a hard block.

### 3. YAML Validation

Run on all modified YAML files:

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/your-file.yml'))"
```

### 4. Justfile Syntax

```bash
just --list
```

**Fix any syntax errors before committing.**

---

## Change-Type-Specific Checklists

### Containerfile / Justfile Changes

| Check                            | Command                                  |
| -------------------------------- | ---------------------------------------- |
| Shellcheck (if scripts modified) | `just lint` (git-scoped `*.sh`)          |
| Hadolint                         | `hadolint Containerfile` (or rely on CI) |
| Justfile syntax                  | `just --list`, `just check`              |
| Unit tests                       | `just test-unit`                         |
| Local build test                 | `just build`                             |

**CI triggers:** `pr-validation.yml` (shellcheck, hadolint), `unit-tests.yml`

### `build/*.sh` Changes

| Check                         | Command                                                                     |
| ----------------------------- | --------------------------------------------------------------------------- |
| Shellcheck all modified `.sh` | `just lint`                                                                 |
| Local build test              | `just build`                                                                |
| bootc lint                    | `bootc container lint --fatal-warnings` in the built image                  |
| Unit tests                    | `just test-contract`                                                        |

`just lint` and CI resolve the same list — `git ls-files '*.sh'` — so a script
outside `build/` is covered by both. A hardcoded `build/*.sh` glob silently
stops covering anything added elsewhere.

**CI triggers:** `pr-validation.yml` (shellcheck), `unit-tests.yml`

### Brewfile Changes

| Check                 | Command                                             |
| --------------------- | --------------------------------------------------- |
| Validate declarations | `just validate-brewfiles`                           |
| List packages         | `brew bundle list --file custom/brew/default.Brewfile` |
| Verify packages exist | covered by `just validate-brewfiles`               |

Never `brew bundle check` a repository Brewfile as a validation step: a Brewfile
is a Ruby DSL, so evaluating a PR-controlled one is code execution in CI.
`build/validate-brewfiles.sh` greps the files and passes names to `brew info` as
data, which is the only safe form. It found `repgrep` in `default.Brewfile` on
its first run.

**CI triggers:** `validate-brewfiles.yml`, `unit-tests.yml`

### Flatpak Changes

| Check                    | Command                                            |
| ------------------------ | -------------------------------------------------- |
| Validate declarations    | `just validate-flatpaks`                           |
| Verify app ID on Flathub | covered by the above (`flatpak remote-info`)        |
| Syntax check             | covered by the above (GKeyFile shape + `Branch=`)  |
| No duplicate app IDs     | Search for existing app IDs in `.preinstall` files |

The validator also rejects lines that are not a comment, a
`[Flatpak Preinstall <app-id>]` header or a `key=value` pair. flatpak logs those
at `g_info` level and then discards the whole file, so malformed syntax looks
identical to an empty preinstall list.

**CI triggers:** `validate-flatpaks.yml`, `unit-tests.yml`

### ujust Changes

| Check                        | Command                                                                |
| ---------------------------- | ---------------------------------------------------------------------- |
| Syntax validation            | `just --list`                                                          |
| Specific file check          | `just --unstable --fmt --check -f custom/ujust/your-file.just`         |
| No `dnf5`/`dnf`/`rpm-ostree` | `grep -E "dnf|rpm-ostree" custom/ujust/*.just` (should return nothing) |

**CI triggers:** `validate-justfiles.yml`

### Workflow Changes

| Check                                        | Command                                                      |
| -------------------------------------------- | ------------------------------------------------------------ |
| Actionlint                                   | `actionlint .github/workflows/*.yml`                         |
| YAML syntax                                  | `python3 -c "import yaml; yaml.safe_load(open('file.yml'))"` |
| Renovate config (if `renovate.json` changed) | `renovate-config-validator .github/renovate.json`            |

**CI triggers:** `pr-validation.yml`, `validate-renovate.yml`

### README Changes

| Check                  | Command                                                                     |
| ---------------------- | --------------------------------------------------------------------------- |
| Markdown linting       | `markdownlint README.md` (if installed) or review manually                  |
| Links valid            | Check all links resolve (click or `curl -I`)                                |
| Raptor section present | Verify "What Makes this Raptor Different?" section exists and is up to date |

**CI triggers:** None by default (consider adding `markdownlint` to pre-commit)

### Repo-wide Doc Sweeps

| Check                   | Command                                                              |
| ----------------------- | -------------------------------------------------------------------- |
| Include dot-directories | `grep -rn "pattern" .github .agents` (don't rely on `grep -r .` alone) |

`.github/` and `.agents/` hold most of this template's docs, skills, and
workflows. A recursive search rooted at `.` can silently skip dot-directories
depending on grep configuration — target them explicitly when auditing docs
for stale claims, and verify every reported location against the real file
before editing.

---

## PR Status Check Reference

| Workflow                 | Trigger Path                  | Required? |
| ------------------------ | ----------------------------- | --------- |
| `pr-validation.yml`      | All PRs                       | Yes       |
| `validate-brewfiles.yml` | `custom/brew/**`              | Yes       |
| `validate-flatpaks.yml`  | `custom/flatpaks/**`          | Yes       |
| `validate-justfiles.yml` | `Justfile`, `custom/ujust/**` | Yes       |
| `validate-renovate.yml`  | `renovate.json`               | Yes       |

All validation workflows must pass before a PR is merged.

## Common Rationalizations

| Rationalization                                                       | Reality                                                                                 |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| "I'll skip shellcheck locally — CI will catch it."                    | CI catches it, but wastes time. Running locally takes 2 seconds.                        |
| "I only changed one line in a workflow — it doesn't need actionlint." | YAML syntax is fragile. Actionlint catches issues `yaml.safe_load` doesn't.             |
| "The PR is small — I don't need the full checklist."                  | The checklist is weighted by change type. Use the relevant section, not the whole list. |
| "I'll fix the Brewfile syntax after the PR is open."                  | `validate-brewfiles.yml` blocks the PR. Fix it before opening.                          |

## Red Flags

- PR opened with shellcheck failures
- Brewfile syntax errors caught in CI instead of locally
- App ID in `.preinstall` not verified on Flathub
- `dnf5` present in a `.just` file
- Workflow YAML with syntax errors (catches `actionlint`, not just CI)
- Missing Conventional Commit format in PR title or commits

## Verification

- [ ] Did you run the pre-commit checklist (conventional commits, shellcheck, YAML, justfile)?
- [ ] Did you run the change-specific checks for your modified files?
- [ ] Do all validation commands pass locally?
- [ ] Does the PR title follow Conventional Commit format?
- [ ] Are all CI status checks green before requesting review?
- [ ] Did you update the README raptor section if packages or configuration changed?
