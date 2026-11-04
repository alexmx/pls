# quick

A command-line runner for automations you write yourself (shell, AppleScript, Shortcuts), with natural-language
"pick & fill" using Apple's on-device Foundation Model. Swift 6 package, macOS 26+. The design is in
[`SPEC.md`](SPEC.md).

Workflow: main

## Commands
- Verify (run before every commit): `xc verify` (format check + lint + build + test)
- Run: `xc quick -- <args>`; try it on the sample library with `QUICK_HOME=examples/home xc quick -- list`
- Fix formatting: `xc format`

## Layout
- `Sources/QuickCore/`: library with everything except terminal I/O, so a future GUI can reuse it
- `Sources/quick/`: the CLI
- `Tests/QuickCoreTests/`: Swift Testing; every top-level suite has `@Suite(.timeLimit(.minutes(1)))` (lint-enforced)
- `examples/home/`: sample library (one of each automation format); doubles as format documentation
- `poc/`: throwaway proof of concept for the model (own package, excluded from format/lint); results in `poc/results/`
- `SPEC.md`: MVP spec and milestones

## Conventions
