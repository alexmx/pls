# pls — MVP spec

A command-line runner for automations you write yourself (shell scripts, AppleScript, Apple Shortcuts),
with natural-language "pick & fill" powered by Apple's on-device Foundation Model.

```
pls run kill-port 3000                    # run by id
pls "something is stuck on port 3000"     # pick & fill with the on-device model, then confirm
```

## 1. Scope

**In the MVP**
- Load automations from `~/.config/pls`: single script files with a comment header, or folders with a `manifest.yaml`.
- Opt-in Apple Shortcuts, registered in `~/.config/pls/shortcuts.yaml`.
- Run automations with typed, validated params; prompt for missing required values.
- Natural language → pick an automation + fill its params (on-device model), always reviewed before running.
- History, `pls again`, `pls doctor`, zsh completion.

**Not in the MVP**: generating or editing scripts with AI, one-off commands, multi-step workflows,
triggers (schedules, file watchers), GUI launcher, Raycast script format, project-local `.pls/` folders,
learning from accepted picks (history records what's needed, see §8).

**Why:** the proof of concept in `poc/` showed the on-device model routes 30/30 requests correctly and fills
params 18/19 in ~1.2s, but writes scripts poorly. The MVP uses the model only for what it's good at.

## 2. Directory layout

What you write and what pls writes live apart, so the first can sit in a dotfiles repo without per-machine noise.

```
~/.config/pls/            # $PLS_HOME, else $XDG_CONFIG_HOME/pls, else ~/.config/pls
  automations/
    kill-port.sh          # single-file automation
    dark-mode.applescript # single-file automation
    compress-images/      # folder automation
      manifest.yaml
      run.sh
  shortcuts.yaml          # opt-in Shortcuts

~/.local/state/pls/       # $PLS_HOME, else $XDG_STATE_HOME/pls, else ~/.local/state/pls
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
`# @pls.` in shell files and `-- @pls.` in AppleScript. Parsing stops at the first line that isn't a comment
or blank.

```bash
#!/bin/zsh
# @pls.name: Kill process on port
# @pls.description: Kill whatever process is listening on a TCP port
# @pls.param port: int(1...65535) -- TCP port number
# @pls.example: free up port 3000
# @pls.example: something is stuck on 8080
lsof -ti tcp:$PLS_PORT | xargs kill
```

```applescript
-- @pls.description: Switch the system appearance between dark and light
-- @pls.param mode: enum(dark|light|toggle) = toggle -- Desired appearance
-- @pls.example: it's too bright
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
  - name: suffix
    type: string
    optional: true              # may be left empty; the manifest form of `string?`
```

Param keys: `name` and `type` (required), `default`, `optional`, `description`, `min` + `max` (int/number, both or
neither), `options` (enum). A param can't be both `optional` and have a `default`. `confirm` and `optional` accept only
`true` / `false` (not YAML's `yes` / `on`). `.scpt` entries are allowed here (kind `applescript`).

### 3.3 Shortcuts (opt-in)

Only Shortcuts listed in `shortcuts.yaml` are part of the library. Manage the file by hand or with `pls shortcuts add/remove`.

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
@pls.param <name>: <type>[?] [= <default>] [-- <description>]
```

- `<name>`: lowercase letters, digits and `_`.
- No default → **required**. A `?` after the type → optional with no default (e.g. `string?`).
- The default is everything between `=` and ` -- `, trimmed; surrounding quotes are removed. A default can't
  contain ` -- ` (even quoted); use the folder form for that.
- Reserved names: `yes`, `dry_run`, `help` (CLI flags), `id`, `automation_dir` (their `PLS_` variables are set by
  pls) and `home`, `model` (their `PLS_` variables are settings, §2 and §7).

### 4.3 Binding order

Final values are built in this order (later wins): defaults → model output (NL only) → CLI arguments → interactive edits.
Values are then validated against their type. A required param that's still missing triggers a prompt
when running in a terminal (re-asked until valid); otherwise pls exits with code 64. An invalid value given on the
command line is an error (64), not a prompt.

## 5. Execution

Scripts run in the user's **current directory**, with stdin/stdout/stderr attached, so interactive scripts work.
pls exits with the script's exit code, or 128 + the signal number if a signal ended it. Ctrl-C reaches the script as
usual; pls waits for it to finish rather than quitting first.

Environment for all kinds:
- `PLS_<NAME>` for every param, with the name in uppercase (`PLS_PORT=3000`). Optional params with no value are unset.
- Every other `PLS_` variable from the calling environment is removed, except the settings `PLS_HOME` and
  `PLS_MODEL`: a `pls run` inside a script is set up the same way but inherits nothing else from the automation that
  called it.
- `PLS_ID`, and for folder automations `PLS_AUTOMATION_DIR` (where its files live).

| Kind | How it's run |
|---|---|
| shell | With a shebang: run directly if executable, otherwise through the shebang's interpreter. Without one: `/bin/zsh <file>`, executable or not. Params are also passed as positional arguments in declared order (unset → empty string). |
| applescript | `osascript <file> <params in declared order>`; read them with `on run argv`. |
| shortcut | `shortcuts run "<name>" --input-path <tmp> --output-path <tmp>`. One param → its value as plain text. Several → a JSON object as text (use *Get Dictionary from Input* in the Shortcut). The output, if any, is printed to stdout. |

## 6. CLI

```
pls list [--json]                      # id, kind, description (--json: everything)
pls show <id>                          # full details, params, source path
pls run <id> [values…] [--<param> <value>…] [-y|--yes] [--dry-run]
pls "<request>" [--yes] [--dry-run]    # natural language
pls again [-y|--yes] [--dry-run]       # re-run the last run with the values you chose
pls history [-n|--limit 20]            # recent runs, newest first
pls shortcuts list                     # all Shortcuts, marking the ones enabled
pls shortcuts add "<name>"             # append an entry to shortcuts.yaml
pls shortcuts remove <id>
pls doctor
pls completion zsh
```

**Dispatch:** a known subcommand (or `help`, `--help`, `--version`) wins; otherwise all arguments joined are a
natural-language request, which also takes `-y`/`--yes` and `--dry-run`. Automations are only ever run by id through
`pls run`, so an id may equal a command name (`pls run list`). A request that starts with a command word needs
quotes: `pls "run the backup"` is one argument, so it's a request; unquoted, `pls run the backup` looks for the id
`the` and, failing, suggests the quoted form.

**Params on the CLI:** positional values fill the params not given by name, in declared order; or `--<name> <value>` /
`--<name>=<value>`, where dashes may stand for underscores (`--older-than-days`). Bools also accept `--<name>` /
`--no-<name>`. A lone `--` makes everything after it positional.

**Confirmation**
- `pls run`: runs immediately, unless the automation has `confirm: true`.
- Natural language: always shows the plan and asks.
- `--yes` skips the question. Without a terminal and without `--yes`, it fails with exit code 64.
- `--dry-run` prints the plan, the exact command and the `PLS_` variables, and exits without asking anything;
  missing values are shown as missing instead of prompted for.
- Prompts, and the plan shown with the confirm question, go to stderr, so stdout carries only the script's
  output. `--dry-run` prints to stdout.

**Plan display** marks where each value came from:

```
→ Compress images  (compress-images)
    folder   ~/Desktop     from request
    quality  60            from request
    format   png           default
  Run? [Y/n/e]
```

`e` edits each param in turn, with the current value prefilled (line editing via libedit), then shows the plan
again. A changed value is marked `edited`; an empty answer resets a param to its default or clears an optional one,
and a required param can't be left empty. Ctrl-D on an empty line, or Ctrl-C, cancels (130). Every confirm question
offers `e`: requests and `confirm: true` automations alike.

While the model works, a terminal shows `Thinking…` on stderr; it's erased before the plan or an error appears.

**Exit codes:** the script's own code when it ran (128 + signal if killed); `64` usage or validation error; `65`
unknown id or no NL match; `69` model unavailable and no fallback chosen; `1` the model couldn't answer a request
(a refusal, an unsupported language, a library too big for its context); `126` the script couldn't be started
(e.g. its shebang interpreter doesn't exist); `130` cancelled at a prompt.

## 7. Natural language (pick & fill)

Two stages, both with greedy (deterministic) sampling and a fresh session each:

1. **Route.** The prompt lists every automation that has a description: `id: description (e.g. "example", …)`.
   The output schema limits the answer to one of those ids or `none`.
2. **Fill** (only if the automation has params). The schema is built from the automation's params:
   every property optional, enums restricted to their options, int/number ranges as guides.
   Instructions: fill only values the request states or clearly implies; never invent.

Only automations with a description are offered to the router. Then the values are merged and validated (§4.3):
a model value that doesn't fit its param is dropped, so the param falls back to its default or is prompted for.
Missing required values are prompted for, and the plan is shown.

- **Fuzzy match:** ranks automations by the words a request shares with their id, name, description and examples
  (lowercased, without filler words such as "the", "my", "what", "make"). A shared word counts 1; the same first 4
  letters count ½ ("darker" / "dark"; "app" / "appearance" is too short to count). Ties go by id.
- **No match (`none`):** print "No automation matches" plus up to 3 closest by fuzzy match; exit 65.
- **Model unavailable** (Apple Intelligence off, unsupported Mac, still downloading, or `PLS_MODEL=off`): print why,
  list the up-to-3 closest by fuzzy match numbered, and ask `Which one?`. The pick gets its defaults, missing values
  are prompted for, and the plan is reviewed as for any request. Picking none (Enter), no shared words, no terminal,
  or `--dry-run` exits 69 after the list; Ctrl-D is 130.
- **`PLS_MODEL=off`** turns the model off for every request, e.g. to keep requests on plain word matching.
- **Context budget:** `doctor` reports the routing list's token count against the model's context size
  (8K on macOS 27). Narrowing the candidates before routing is post-MVP; the list is ~35 tokens per automation.

## 8. History

Every run whose script started appends one JSON line to the history file (§2), after the script ends, failed runs
included. Dry runs, invalid values, cancelled prompts and scripts that couldn't start (126) aren't recorded. If the
file can't be written, pls prints a warning and keeps the script's exit code. Each line is a single append, so runs
finishing at the same time don't interleave; lines that can't be read are skipped.

```json
{"at":"2026-11-04T19:30:00Z","chosen":["port"],"exit":0,"id":"kill-port","params":{"port":"3000"},"seconds":0.4,
 "via":"run"}
```

- `params`: every value the run used, defaults included. `chosen`: the ones typed, entered at a prompt, repeated,
  read from the request or edited in review, as opposed to defaulted.
- `via`: `run`, `again` or `request`. A request also records `request` (the words) and `edited` (whether the plan
  was changed before running), the data "learn from accepted picks" needs. `pls again` replays a request's values,
  edits included, without the words.

`pls history` shows recent runs: time, automation, the chosen values, ok or the exit code, and duration.

`pls again` repeats the newest entry against the automation as it is now, without asking the model again:
- chosen values are replayed (shown as "last run"); defaults come from the current automation, so a changed default
  is picked up;
- params the automation no longer has are dropped; required params it has gained are asked for in a terminal
  (exit 64 without one);
- a replayed value that no longer fits its param is exit 64; no history, or an automation that's gone, is exit 65;
- it prints what it repeats, asks first for `confirm: true` automations unless `--yes`, and is recorded itself.

## 9. Doctor

Reports each problem with its file (and line, where known). Errors mean the automation can't be used and
is left out of the library; warnings don't. Exits 1 if there's any error, 0 otherwise.

Errors:
- header or manifest parse errors, missing entry files
- duplicate ids, invalid id characters
- enabled Shortcuts that no longer exist

Warnings:
- the library folder doesn't exist (e.g. a mistyped `PLS_HOME`); unreadable is an error
- unknown header or manifest keys
- missing `description` (not offered to the model)
- shell files without a shebang (they run with `/bin/zsh`)

Info: model availability, plus the routing list's token count vs. the context size.

## 10. Code structure

Swift package, macOS 26+. Dependencies: `swift-argument-parser`, `Yams`.

```
Sources/
  PlsCore/                # no terminal or UI code, so a future GUI can reuse it
    Model/                # Automation, Param, ParamType, ParamValue
    Library/              # HeaderParser, ManifestParser, ShortcutsRegistry, Library (merges sources)
    Resolve/              # ParamBinder (defaults/CLI/model → validated values), NLResolver, FuzzyMatcher
    Run/                  # Runner protocol; ShellRunner, AppleScriptRunner, ShortcutRunner
    History/
  pls/                    # CLI: dispatch, prompts, plan display, completion
  CEditLine/              # C wrapper for libedit (ships with macOS): prompts with a prefilled, editable line
Tests/PlsCoreTests/       # parsers, binder, dispatch, runners (with fixture scripts)
Evals/                    # `xc evals`: NL eval set, ported from poc/ (needs the model, not run in `swift test`)
  library/                # 18 stub automations the requests resolve against
  cases.yaml              # requests with the expected pick and values
  Sources/, Tests/        # runner and its scorer tests (those do run in `swift test`)
  results/baseline.txt    # last accepted run, to compare a change against
```

Natural-language dispatch (§6) happens before ArgumentParser, which handles the subcommands themselves.

## 11. Milestones

1. **Library:** both automation formats + `list`, `show`, `doctor`.
2. **Runner:** shell + AppleScript runners, `run` with params, prompts, `--dry-run`; then history, `history` and `again`.
3. **Natural language:** pick & fill, review/edit, fuzzy fallback, eval set.
4. **Shortcuts:** `shortcuts.yaml`, runner, `shortcuts list/add/remove`.
5. **Polish:** zsh completion, exit codes, error messages.

## 12. Later

Raycast script format, learning from accepted picks (history → extra examples), project-local `.pls/`,
JXA, candidate narrowing for large libraries, multi-step workflows, triggers, GUI launcher,
and script generation with a bigger model (Private Cloud Compute or an external provider).
