---
name: use-pls
description: Write automations for pls, the macOS command-line runner that picks and fills automations from plain-language requests with Apple's on-device model. Use this whenever the user wants to add, write, fix or improve a pls automation, turn a shell script, AppleScript or Shortcut into one, make something runnable as `pls "<request>"`, or edits files in a pls library (`~/.config/pls/automations`, `$PLS_HOME/automations`), including `@pls.` headers and `manifest.yaml` files, even if they only say "automate this" in a project that uses pls.
---

# Writing pls automations

pls runs automations the user owns: shell scripts and AppleScript (which can call Shortcuts). Each one declares a
description, examples and typed params. Then `pls "free up port 3000"` has Apple's small on-device model pick the
automation and fill its params, shows the plan, and runs it; `pls run kill-port 3000` runs it directly.

A "pls ready" automation loads with no problems in `pls doctor`, gets picked for the requests it should handle (and
not for others), and gets correct values. The model is small and so is its context, so what you write in the
description, examples and params is most of what it has to go on.

## Workflow

1. Find the library: run `pls doctor` and read its first line, `Library: <folder>`. Write automations directly in
   that folder. (It's `$PLS_HOME/automations`, else `$XDG_CONFIG_HOME/pls/automations`, else
   `~/.config/pls/automations`.) Look at what's there first: reuse its style, and don't add an automation whose
   purpose overlaps an existing one; that makes routing ambiguous.
2. Write the automation in one of the two formats below.
3. Check what pls sees, and fix everything reported:
   - `pls doctor`: no errors or warnings for your file. An automation with an error is left out entirely.
   - `pls show <id>`: the params, types and defaults are what you meant.
   - `pls run <id> --dry-run <values>`: the exact command and variables pls would run.
   - `pls doctor --examples <id>`: each of your examples picks your automation, not a neighbour (needs Apple
     Intelligence; doctor's `Model:` line says whether it's available). A miss means requests worded like it miss too:
     reword the description or examples, or try another id (the model can favour one id over another).
   - `pls "<a phrasing that isn't an example>" --dry-run`: routes to your automation with the right values.
4. Check the script itself: everything in step 3 passes even when the script can't run. Run it directly, the way pls
   would, with the variables set: `PLS_DAYS=30 PLS_FOLDER=/tmp/fixture zsh <file>` (`osascript <file> <values…>` for
   AppleScript). When it deletes, moves or overwrites things, run it on throwaway data made for the test (a scratch
   folder; `touch -t 202401010000 <file>` for old dates) and check what's left, never on the user's real files. When
   it acts on the outside world (sends, logs, changes settings) and a harmless run isn't possible, at least check that
   it parses (`zsh -n <file>`, `osacompile -o /dev/null <file>`) and say it wasn't run.

## Format 1: a single file with a header

The id is the file name without its extension: `kill-port.sh` → `kill-port`. Ids are lowercase kebab-case.
`.applescript` files use `--` comments; any other file is a shell script with `#` comments. The header is the
comment block at the top (after an optional shebang); parsing stops at the first line of code.

```zsh
#!/bin/zsh
# @pls.name: Kill process on port
# @pls.description: Kill whatever process is listening on a TCP port
# @pls.param port: int(1...65535) -- TCP port number
# @pls.example: free up port 3000
# @pls.example: something is stuck on 8080

pids=$(lsof -ti tcp:"$PLS_PORT")
if [[ -z $pids ]]; then
  echo "Nothing is listening on port $PLS_PORT."
  exit 0
fi
echo "$pids" | xargs kill && echo "Killed the process(es) on port $PLS_PORT."
```

Keys:

- `@pls.description: <text>` — what it does, one line. Without it, requests never pick the automation.
- `@pls.example: <text>` — a request that should pick it; repeat the line for each one.
- `@pls.param <name>: <type>[?] [= <default>] [-- <description>]` — one per param, in order.
- `@pls.name: <text>` — display name; defaults to the id in words (`kill-port` → "Kill port").
- `@pls.confirm: true` — always ask before running, even with `pls run`. `@pls.confirm: action=shutdown,restart` asks
  only when that param has one of those values (here not for `cancel`).
- `@pls.background: true` — run detached as a job instead of holding the terminal (see Script conventions).
- `@pls.preview: true` — the script supports a preview run that says what it would do (see Script conventions).

## Format 2: a folder with manifest.yaml

Use a folder when the automation needs files of its own, or is a compiled `.scpt` (which can't hold a header). The
folder name is the id.

```yaml
# compress-images/manifest.yaml
name: Compress images
description: Re-encode images in a folder at lower quality to reduce file size
entry: run.sh            # the file to run, relative to the folder
examples:
  - shrink my screenshots
  - make the jpgs on my desktop smaller
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
    options: [jpg, heic]
    default: jpg
    description: Which image type to compress
```

Also `background: true`, `preview: true`, `confirm: true` (or `confirm: {action: [shutdown, restart]}` to ask only
for those values), `optional: true` on a param, and `kind: shell | applescript` (only needed when the entry's
extension doesn't say: `.applescript` and `.scpt` are AppleScript, anything else is shell). The entry file needs no
header. Its folder is in `$PLS_AUTOMATION_DIR`, for reaching the files next to it.

## Params

Types, header syntax / manifest fields:

| Type | Header | Manifest | Value the script gets |
|---|---|---|---|
| text | `string` | `type: string` | as given |
| file or folder | `path` | `type: path` | as given, with a leading `~` expanded |
| yes/no | `bool` | `type: bool` | `true` or `false` |
| whole number | `int`, `int(1...100)` | `type: int`, `min`, `max` | digits |
| number | `number`, `number(0...1)` | `type: number`, `min`, `max` | e.g. `0.5`, `2` |
| one of a list | `enum(a\|b\|c)` | `type: enum`, `options: [a, b, c]` | one of the options |

Each param is required (asked for if missing), optional (`name: string?` / `optional: true`; may be left empty, no
default) or has a default (`= value` / `default: value`); never both optional and defaulted. Defaults must be valid
for the type. Names are lowercase letters, digits and `_`, starting with a letter. These names are reserved:
`automation_dir`, `dry_run`, `help`, `home`, `id`, `model`, `preview`, `yes`.

## How values reach the script

- Shell: each param is in `$PLS_<NAME>` (`older_than_days` → `$PLS_OLDER_THAN_DAYS`), and also passed as positional
  arguments in declared order. Prefer the variables: they're named. An optional param left empty is unset, and its
  positional argument is `""`.
- AppleScript: `on run argv` gets the values in declared order, as text (`item 1 of argv`); an empty optional is `""`.
  Convert numbers and bools yourself (`(item 2 of argv) as integer`, `(item 3 of argv) is "true"`).
- `$PLS_ID` is the automation's id. Every other `PLS_` variable from the caller is removed, except `PLS_HOME` and
  `PLS_MODEL`, so a script can call `pls run <other-id>` itself.
- The script runs in the user's current folder with the terminal attached: it can print, prompt and be stopped with
  Ctrl-C. A relative `path` value is relative to that folder, so don't `cd` before using it.
- A shell script runs through its shebang (executable or not); with no shebang it runs with `/bin/zsh` and doctor
  warns. pls exits with the script's exit code.

## Writing for the model

Routing sees one line per automation: `- <id>: <description> (e.g. "<example>", …)`. In a library of more than 30
automations it first sees only the 10 closest to the request by meaning, judged by the description and examples, so
those also decide whether an automation is considered at all. Filling then sees the
automation's name and description plus one line per param: `- <name> (<type>): <description> [default: <value>]`.
That's all it knows, so:

- **Description**: start with a verb and say what it acts on and what changes, in plain words: "Kill whatever process
  is listening on a TCP port", not "Port utility". Make it distinct from the library's other descriptions. Keep it
  to one short sentence: every description goes into the model's context on every request (doctor reports how much
  of it routing takes).
- **Examples**: 2–4 requests the way a person would type them, varied: one direct ("turn on dark mode"), one
  indirect that names the problem, not the action ("it's too bright"), one with values in it ("free up port 3000").
  They teach the routing; they aren't matched literally.
- **Params**: few, and as constrained as the job allows. A small model fills an `enum` or a ranged `int` far more
  reliably than free `string`s, so use `enum` for any fixed set of choices and give ranges to numbers. Give a
  default whenever a sensible one exists: a request without that value then still runs, where otherwise the model
  tends to make a value up. Describe each param with its unit or meaning ("How long, in minutes; 0 means until
  turned off"), since the description is how the model maps the user's words to it. Pick enum options that are
  words a user would say (`dark|light|toggle`).
- **No example values in descriptions**: the model copies them into requests that don't give a value ("a voice, like
  Samantha" made Samantha the voice of every request; "e.g. 1200 pixels" became the size). Say what a value means
  instead, and add "only when the request names one" if the model keeps filling it.
- **Optional choices and numbers get a default**: an optional `enum` or `int` with no default gets a value made up
  for it anyway (`port 1` for "which ports are open?"). Give it a default that means "all" or "unchanged", like
  `port: int(0...65535) = 0` with "0 shows every port".
- **Default to the common action, not `toggle`**: a guessed default must not do the opposite of what was asked.
  `mute` defaults to `mute`, so "volume 0" mutes even when the sound is already muted.
- **Link the user's words to each choice** in the param's description: "png for screenshots, jpg for photos, heic
  for iPhone photos" fills far better than a bare list of formats.
- **Split an automation that does two things** (set a folder *or* a format) into two: a small model fills one
  purpose reliably and keeps inventing values for the other.
- Leave the id, name and description free of jargon the user wouldn't use. When a request keeps going to a
  neighbour no matter the wording, try another id: the model favours some ids over others, and `image-resize`
  routed where `resize-images` didn't.

## Script conventions

- Start shell scripts with a shebang (`#!/bin/zsh` or `#!/bin/bash`) and quote every `"$PLS_…"` expansion.
- In zsh, don't name your own variables after zsh's special ones. `status`, `modules`, `history` and `parameters`
  are read-only (assigning one stops the script), `commands`, `options`, `functions` and `aliases` are tables, and
  `path` *is* `$PATH`, so `path=...` quietly breaks every later command. Prefer specific names: `nm_dir`,
  `target`.
- Print one short line saying what happened ("Killed 2 processes on port 3000."), including when there was nothing
  to do. Exit non-zero on failure, with the reason on stderr.
- Set `confirm: true` for anything destructive or hard to undo (deleting, killing, sending, overwriting). Requests
  always show the plan and ask anyway; `confirm` makes `pls run` ask too. When only some choices are risky, name them
  (`confirm: action=erase`) instead of asking for every run, and don't ask from inside the script.
- For something that keeps running (keep awake, a countdown, a delayed shutdown), set `@pls.background: true` rather
  than backgrounding it yourself with `&`, `nohup` or a pid file. pls starts it detached, prints its first line of
  output, and `pls jobs` lists it; running the automation again replaces the job, and `pls jobs stop <id>` ends it
  with everything it started. So print one line saying what's happening first, then wait (`exec sleep`, `exec
  caffeinate`, …). A param value that only stops the job (`minutes 0`) works by replacing it with a run that just
  prints and exits.
- For something that deletes, moves or overwrites, consider `@pls.preview: true`: pls then also runs the script with
  `PLS_PREVIEW=1` for `--dry-run` and before asking "Run?", and shows what it prints. In a preview the script must
  change nothing, so check it first: `if [[ -n $PLS_PREVIEW ]]; then echo "Would trash 23 items (1.4 GB)"; exit 0;
  fi`. A preview has no input and should be quick. Without the key, pls never runs the script for a dry run.
- Prefer writing results next to the input over overwriting it (compressed copies go in `<folder>/compressed`).
- Don't hardcode the user's paths or their home; take a `path` param with a `~/…` default instead.

## Sharing them as a collection

To share automations, put them in a GitHub repo with an `automations/` folder at its root, in either format, exactly
as in a library. Others install it with `pls collection add <owner>/<repo>`, and `pls collection update` pulls your
changes. Each automation must stand on its own: no paths into your home folder, no files outside its own folder,
and the description and examples written for anyone's library, since they'll route among other people's
automations.

## Shortcuts

There's no Shortcut format: wrap one in a shell script that calls `shortcuts run "<name>"`. A Shortcut takes one
input, so for several params write them as JSON to a temporary file and have the Shortcut start with "Get
Dictionary from Input":

```zsh
#!/bin/zsh
# @pls.description: Turn a macOS Focus mode on or off, optionally for a number of minutes
# @pls.param mode: enum(do-not-disturb|work|sleep|off) = do-not-disturb -- Which Focus
# @pls.param minutes: int(0...1440) = 0 -- How long; 0 means until turned off
# @pls.example: do not disturb for an hour
# @pls.example: turn off focus

input=$(mktemp -t pls-focus) || exit 1
trap 'rm -f "$input"' EXIT
printf '{"mode": "%s", "minutes": %s}\n' "$PLS_MODE" "$PLS_MINUTES" > "$input"
shortcuts run "Set Focus" --input-path "$input"
```

`shortcuts list` shows the user's Shortcuts. If the Shortcut doesn't exist yet, tell the user exactly what it must
do with the input; you can't create it for them.

## AppleScript example

```applescript
-- @pls.description: Switch the system appearance between dark and light
-- @pls.param mode: enum(dark|light|toggle) = toggle -- Desired appearance
-- @pls.example: it's too bright
-- @pls.example: turn on dark mode

on run argv
	set mode to item 1 of argv
	tell application "System Events"
		tell appearance preferences
			if mode is "toggle" then
				set dark mode to not dark mode
			else
				set dark mode to (mode is "dark")
			end if
		end tell
	end tell
end run
```

The first time an AppleScript controls an app, macOS asks the user for permission; mention that if it's likely.
Inside a `tell application` block, the app's own terms are reserved: `paused` in Music doesn't compile as a variable
name, so pick names like `stateNote`, and run `pls doctor`, which compiles every AppleScript. To fail, use `error
"No image at /x.jpg"`: pls shows just that message.
