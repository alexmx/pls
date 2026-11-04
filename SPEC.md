# quick — MVP spec

A command-line runner for automations you write yourself (shell scripts, AppleScript, Apple Shortcuts),
with natural-language "pick & fill" powered by Apple's on-device Foundation Model.

```
quick run kill-port 3000              # run by id
quick "something is stuck on port 3000"   # pick & fill with the on-device model, then confirm
```

## 1. Scope

**In the MVP**
- Load automations from `~/.quick`: single script files with a comment header, or folders with a `manifest.yaml`.
- Opt-in Apple Shortcuts, registered in `~/.quick/shortcuts.yaml`.
- Run automations with typed, validated params; prompt for missing required values.
- Natural language → pick an automation + fill its params (on-device model), always reviewed before running.
- History, `quick again`, `quick doctor`, zsh completion.

**Not in the MVP**: generating or editing scripts with AI, one-off commands, multi-step workflows,
triggers (schedules, file watchers), GUI launcher, Raycast script format, project-local `.quick/` folders,
learning from accepted picks (history records what's needed, see §8).

**Why:** the proof of concept in `poc/` showed the on-device model routes 30/30 requests correctly and fills
params 18/19 in ~1.2s, but writes scripts poorly. The MVP uses the model only for what it's good at.

## 2. Directory layout

```
~/.quick/                 # override with $QUICK_HOME
  automations/
    kill-port.sh          # single-file automation
    dark-mode.applescript # single-file automation
    compress-images/      # folder automation
      manifest.yaml
      run.sh
  shortcuts.yaml          # opt-in Shortcuts
  history.jsonl
```

No config file in the MVP.

## 3. Automations

Every automation has:

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Lowercase kebab-case, unique. From the file or folder name. |
| `name` | no | Defaults to the id with title case, e.g. `kill-port` → "Kill port". |
| `description` | for NL | One sentence. Without one, the automation isn't offered to the model (`doctor` warns). |
| `kind` | inferred | `shell`, `applescript` or `shortcut`. |
| `params` | no | Ordered list, see §4. |
| `examples` | no | Phrases that should pick this automation. Help the model a lot. |
| `confirm` | no | `true` = always ask before running, even when run by id. For destructive automations. |

### 3.1 Single file

Any file directly inside `automations/`. The id is the filename without extension.

| Extension | Kind |
|---|---|
| `.applescript` | applescript |
| anything else (`.sh`, `.zsh`, `.py`, none, …) | shell (run via shebang, see §5) |

Compiled `.scpt` files can't carry a text header, so they must use the folder form.

The header is the block of comment lines at the top of the file (after an optional shebang). Lines start with
`# @quick.` in shell files and `-- @quick.` in AppleScript. Parsing stops at the first line that isn't a comment
or blank.

```bash
#!/bin/zsh
# @quick.name: Kill process on port
# @quick.description: Kill whatever process is listening on a TCP port
# @quick.param port: int(1...65535) -- TCP port number
# @quick.example: free up port 3000
# @quick.example: something is stuck on 8080
lsof -ti tcp:$QUICK_PORT | xargs kill
```

```applescript
-- @quick.description: Switch the system appearance between dark and light
-- @quick.param mode: enum(dark|light|toggle) = toggle -- Desired appearance
-- @quick.example: it's too bright
on run argv
    set mode to item 1 of argv
    ...
end run
```

Header keys: `name`, `description`, `param` (repeatable), `example` (repeatable), `confirm` (`true`/`false`).
Unknown keys are reported by `doctor` and otherwise ignored.

### 3.2 Folder

A folder inside `automations/` containing `manifest.yaml`. The id is the folder name.

```yaml
name: Compress images
description: Re-encode images in a folder at lower quality to reduce file size
entry: run.sh               # file inside the folder; kind inferred from it as in §3.1
# kind: applescript         # optional override, e.g. for entry: script.scpt
confirm: false
examples:
  - shrink my screenshots
params:
  - name: folder
    type: path
    default: ~/Desktop
    description: Folder containing the images
  - name: quality
    type: int
    min: 1
    max: 100
    default: 80
    description: Output quality percent
  - name: format
    type: enum
    options: [png, jpg, heic]
    default: png
```

`.scpt` entries are allowed here (kind `applescript`).

### 3.3 Shortcuts (opt-in)

Only Shortcuts listed in `shortcuts.yaml` are part of the library. Manage the file by hand or with `quick shortcuts add/remove`.

```yaml
- shortcut: Set Focus            # exact name in the Shortcuts app
  id: focus                      # optional; default is the name in kebab-case
  description: Turn a Focus mode on or off for a number of minutes
  examples: [do not disturb for an hour]
  params:
    - { name: mode, type: enum, options: [do-not-disturb, work, sleep, off] }
    - { name: minutes, type: int, default: 0 }
```

`description` defaults to the shortcut's name. `params` uses the same structure as manifests.

## 4. Params

### 4.1 Types

| Type | Header form | Passed as |
|---|---|---|
| string | `string` | as-is |
| path | `path` | `~` expanded to an absolute path; doesn't need to exist |
| int | `int` or `int(1...100)` | decimal |
| number | `number` or `number(0...1)` | decimal |
| bool | `bool` | `true` / `false` |
| enum | `enum(a\|b\|c)` | one of the options |

### 4.2 Header param syntax

```
@quick.param <name>: <type>[?] [= <default>] [-- <description>]
```

- `<name>`: lowercase letters, digits and `_`.
- No default → **required**. A `?` after the type → optional with no default (e.g. `string?`).
- The default is everything between `=` and ` -- `, trimmed; surrounding quotes are removed.
- Reserved names: `yes`, `dry_run`, `help`.

### 4.3 Binding order

Final values are built in this order (later wins): defaults → model output (NL only) → CLI arguments → interactive edits.
Values are then validated against their type. A required param that's still missing triggers a prompt
when running in a terminal; otherwise quick exits with code 64.

## 5. Execution

Scripts run in the user's **current directory**, with stdin/stdout/stderr attached, so interactive scripts work.
quick exits with the script's exit code.

Environment for all kinds:
- `QUICK_<NAME>` for every param, with the name in uppercase (`QUICK_PORT=3000`). Optional params with no value are unset.
- `QUICK_ID`, and for folder automations `QUICK_AUTOMATION_DIR` (where its files live).

| Kind | How it's run |
|---|---|
| shell | If executable, run directly. Otherwise use the shebang interpreter, or `/bin/zsh` if there's no shebang. Params are also passed as positional arguments in declared order (unset → empty string). |
| applescript | `osascript <file> <params in declared order>`; read them with `on run argv`. |
| shortcut | `shortcuts run "<name>" --input-path <tmp> --output-path <tmp>`. One param → its value as plain text. Several → a JSON object as text (use *Get Dictionary from Input* in the Shortcut). The output, if any, is printed to stdout. |

## 6. CLI

```
quick list [--json]                    # id, name, kind, description
quick show <id>                        # full details, params, source path
quick run <id> [values…] [--<param> <value>…] [--yes] [--dry-run]
quick <id> [values…]                   # same as run
quick "<request>" [--yes] [--dry-run]  # natural language
quick again                            # re-run the last run with the same params
quick history [-n 20]
quick shortcuts list                   # all Shortcuts, marking the ones enabled
quick shortcuts add "<name>"           # append an entry to shortcuts.yaml
quick shortcuts remove <id>
quick doctor
quick completion zsh
```

**Dispatch:** a known subcommand wins → else the first argument is an automation id → else all arguments joined
are a natural-language request. Automation ids that clash with subcommands are reported by `doctor`.

**Params on the CLI:** positional values in declared order, or `--<name> <value>`. Bools also accept `--<name>` / `--no-<name>`.

**Confirmation**
- By id: runs immediately, unless the automation has `confirm: true`.
- Natural language: always shows the plan and asks.
- `--yes` skips every prompt. Without a terminal and without `--yes`, prompts fail with exit code 64.
- `--dry-run` prints the plan and exits.

**Plan display** marks where each value came from:

```
→ Compress images  (compress-images)
    folder   ~/Desktop     from request
    quality  60            from request
    format   png           default
  Run? [Y/n/e]
```

`e` edits each param in turn, with the current value prefilled.

**Exit codes:** the script's own code when it ran; `64` usage or validation error; `65` unknown id or no NL match;
`69` model unavailable and no fallback chosen; `130` cancelled at a prompt.

## 7. Natural language (pick & fill)

Two stages, both with greedy (deterministic) sampling and a fresh session each:

1. **Route.** The prompt lists every automation that has a description: `id: description (e.g. "example", …)`.
   The output schema limits the answer to one of those ids or `none`.
2. **Fill** (only if the automation has params). The schema is built from the automation's params:
   every property optional, enums restricted to their options, int/number ranges as guides.
   Instructions: fill only values the request states or clearly implies; never invent.

Then the values are merged and validated (§4.3), missing required values are prompted for, and the plan is shown.

- **No match (`none`):** print "No automation matches" plus the 3 closest by fuzzy match; exit 65.
- **Model unavailable** (Apple Intelligence off, unsupported Mac): fall back to fuzzy matching on
  id/name/description/examples, show the top 3 to choose from, then prompt for params.
- **Context budget:** `doctor` reports the routing list's token count against the model's context size
  (8K on macOS 27). Narrowing the candidates before routing is post-MVP; the list is ~35 tokens per automation.

## 8. History

Every run appends one JSON line to `history.jsonl`:

```json
{"at":"2026-11-04T19:30:00Z","id":"kill-port","params":{"port":"3000"},"source":"nl",
 "request":"something is stuck on 3000","edited":false,"exit":0,"seconds":0.4}
```

`quick again` re-runs the last entry with the same params, without asking the model again. Saving `request` and
`edited` now makes "learn from accepted picks" possible later without a migration.

## 9. Doctor

Reports each problem with its file (and line, where known). Errors mean the automation can't be used and
is left out of the library; warnings don't. Exits 1 if there's any error, 0 otherwise.

Errors:
- header or manifest parse errors, missing entry files
- duplicate ids, invalid id characters
- enabled Shortcuts that no longer exist

Warnings:
- unknown header or manifest keys
- ids that clash with subcommands
- missing `description` (not offered to the model)
- non-executable shell files without a shebang (they run with `/bin/zsh`)

Info: model availability, plus the routing list's token count vs. the context size.

## 10. Code structure

Swift package, macOS 26+. Dependencies: `swift-argument-parser`, `Yams`.

```
Sources/
  QuickCore/              # no terminal or UI code, so a future GUI can reuse it
    Model/                # Automation, Param, ParamType, ParamValue
    Library/              # HeaderParser, ManifestParser, ShortcutsRegistry, Library (merges sources)
    Resolve/              # ParamBinder (defaults/CLI/model → validated values), NLResolver, FuzzyMatcher
    Run/                  # Runner protocol; ShellRunner, AppleScriptRunner, ShortcutRunner
    History/
  quick/                  # CLI: dispatch, prompts, plan display, completion
Tests/QuickCoreTests/     # parsers, binder, dispatch, runners (with fixture scripts)
Evals/                    # NL eval set + runner, ported from poc/ (not run in `swift test`)
```

Dispatch (§6) happens before ArgumentParser, which handles the subcommands themselves.

## 11. Milestones

1. **Library:** both automation formats + `list`, `show`, `doctor`.
2. **Runner:** shell + AppleScript runners, `run` with params, prompts, `--dry-run`, history, `again`.
3. **Natural language:** pick & fill, review/edit, fuzzy fallback, eval set.
4. **Shortcuts:** `shortcuts.yaml`, runner, `shortcuts list/add/remove`.
5. **Polish:** zsh completion, exit codes, error messages.

## 12. Later

Raycast script format, learning from accepted picks (history → extra examples), project-local `.quick/`,
JXA, candidate narrowing for large libraries, multi-step workflows, triggers, GUI launcher,
and script generation with a bigger model (Private Cloud Compute or an external provider).
