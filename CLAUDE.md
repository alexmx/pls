# pls

A command-line runner for automations you write yourself (shell and AppleScript, which can wrap Shortcuts), with
natural-language "pick & fill" using Apple's on-device Foundation Model. Swift 6 package, macOS 26+.

Workflow: main

## Commands
- Verify (run before every commit): `xc verify` (format check + lint + build + test)
- Run: `xc pls -- <args>`; try it on the sample library with `PLS_HOME=examples/home xc pls -- list`
- Fix formatting: `xc format`
- Model evals: `xc evals` (needs Apple Intelligence, ~40s); compare with `Evals/results/baseline.txt` before changing
  prompts, schemas or the routing list, and update the baseline when a change is accepted

## Releasing
- Bump `.pls-version` on `main` and push; commit it as `fix: bump version to X.Y.Z`. `.github/workflows/release.yml`
  tags `vX.Y.Z`, publishes the arm64 binary and updates `Formula/pls.rb` in alexmx/homebrew-tools (needs the
  `HOMEBREW_TAP_TOKEN` secret). Its push trigger, and CI's, are commented out until the repo is public; both run by
  hand from the Actions tab meanwhile.
- `pls --version` says `dev` outside a release build; the workflow writes the version into `Sources/PlsCore/Pls.swift`.
- CI runs on the `xcode-27` runner: pls needs the macOS 27 SDK.

## Layout
- `Sources/PlsCore/`: library with everything except terminal I/O, so a future GUI can reuse it
- `Sources/pls/`: the CLI
- `Evals/`: eval library, cases and runner for the model (`xc evals`)
- `Sources/CEditLine/`: tiny C wrapper for libedit, which the CLI's prompts read lines through
- `Tests/PlsTests/`: tests for the CLI's own code (the zsh completion script; exit codes, error messages and
  terminal behaviour, run against the built `pls` through `BuiltPls`)
- `Tests/PlsCoreTests/`: Swift Testing; every top-level suite has `@Suite(.timeLimit(.minutes(1)))` (lint-enforced)
- `skills/use-pls/SKILL.md`: the agent skill, embedded into `PlsCore` through the `Resources/SKILL.md` symlink
- Background jobs (`@pls.background`, `pls jobs`): `JobStore` starts them detached in their own process group and
  tracks them in `<state>/jobs/`
- Collections (`pls collection`): GitHub repos with an `automations/` folder, cloned into
  `<home>/collections/<owner>/<repo>` (`CollectionStore`), loaded after your own automations by `Library`. Tests use
  local git repos as the clone source, never the network
- `examples/home/`: sample library (each automation format, plus a Shortcut wrapper); doubles as format documentation

## Conventions
- Child processes go through swift-subprocess, in the app and the tests, never Foundation's `Process`
- `skills/use-pls/SKILL.md` is the guide agents write automations from (`pls skill` prints it; skill installers read
  it from the repo): update it when an automation format, param type or how values reach a script changes. Tests
  keep its examples valid, not complete.
