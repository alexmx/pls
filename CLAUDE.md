# pls

A command-line runner for automations you write yourself (shell, AppleScript, Shortcuts), with natural-language
"pick & fill" using Apple's on-device Foundation Model. Swift 6 package, macOS 26+. The design is in
[`SPEC.md`](SPEC.md).

Workflow: main

## Commands
- Verify (run before every commit): `xc verify` (format check + lint + build + test)
- Run: `xc pls -- <args>`; try it on the sample library with `PLS_HOME=examples/home xc pls -- list`
- Fix formatting: `xc format`
- Model evals: `xc evals` (needs Apple Intelligence, ~40s); compare with `Evals/results/baseline.txt` before changing
  prompts, schemas or the routing list, and update the baseline when a change is accepted

## Layout
- `Sources/PlsCore/`: library with everything except terminal I/O, so a future GUI can reuse it
- `Sources/pls/`: the CLI
- `Evals/`: eval library, cases and runner for the model (`xc evals`)
- `Sources/CEditLine/`: tiny C wrapper for libedit, which the CLI's prompts read lines through
- `Tests/PlsCoreTests/`: Swift Testing; every top-level suite has `@Suite(.timeLimit(.minutes(1)))` (lint-enforced)
- `examples/home/`: sample library (one of each automation format); doubles as format documentation
- `poc/`: throwaway proof of concept for the model (own package, excluded from format/lint); results in `poc/results/`
- `SPEC.md`: MVP spec and milestones

## Conventions
