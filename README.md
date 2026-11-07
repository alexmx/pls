# pls

Run your own automations from the command line, by name or in plain words.

```
$ pls "something is stuck on port 3000"
→ Kill process on port  (kill-port)
    port  3000  from request
  Run? [Y/n/e]
Killed 1 process(es) on port 3000.
```

pls runs automations you write yourself: shell scripts and AppleScript, which can also run Shortcuts. Each one
declares a description, a few example requests and typed params. Ask in plain words and Apple's on-device model picks
the automation and fills its values; pls shows the plan and asks before running it. Nothing leaves your Mac.

## Requirements

- macOS 26 or later
- For plain-language requests: Apple Intelligence turned on. Without it, `pls "<request>"` offers the closest
  automations by shared words instead, and everything else works the same.
- To build: Swift 6.2 (Xcode 26)

## Install

```sh
brew install alexmx/tools/pls
```

Or build it yourself:

```sh
git clone https://github.com/alexmx/pls.git
cd pls
swift build -c release
sudo cp .build/release/pls /usr/local/bin/   # or any folder on your PATH
```

Tab completion for zsh: add `source <(pls completion zsh)` to `~/.zshrc`, after `compinit`.

## Usage

```sh
pls "make the jpgs on my desktop smaller"   # a request in plain words
pls run compress-images ~/Pictures --quality 60
pls again                                   # the last run, with the same values
pls list                                    # your automations
pls show compress-images                    # one in detail
pls history                                 # recent runs
pls jobs                                    # automations running in the background; pls jobs stop <id> ends one
pls doctor                                  # check your automations, and whether the model can be used
```

`--dry-run` shows what would run without running it, and `--yes` skips the question before a run.

## Writing automations

Automations live in `~/.config/pls/automations` (or `$XDG_CONFIG_HOME/pls/automations`, or
`$PLS_HOME/automations`). A single script declares itself in a comment header; the file name is its id:

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
echo "$pids" | xargs kill && echo "Killed $(echo "$pids" | wc -l | tr -d ' ') process(es) on port $PLS_PORT."
```

Params arrive as `$PLS_<NAME>` variables (and as arguments, in order). Types are `string`, `path`, `bool`, `int`,
`number` and `enum`, with optional ranges, defaults and descriptions. An automation that needs files of its own is a
folder with a `manifest.yaml` instead.

[`examples/home`](examples/home/automations) has one automation in each format, including AppleScript and a Shortcut
wrapper. Try them without touching your own library:

```sh
PLS_HOME=examples/home pls list
PLS_HOME=examples/home pls "turn on dark mode" --dry-run
```

## Let your coding agent write them

pls ships an [Agent Skill](skills/use-pls/SKILL.md) that teaches coding agents such as Claude Code the formats, how to
write descriptions and params the small on-device model routes and fills well, and how to check the result. Install
it from this repository with any tool that installs skills from GitHub, or from pls itself:

```sh
mkdir -p ~/.claude/skills/use-pls && pls skill > ~/.claude/skills/use-pls/SKILL.md
```

Then ask your agent for an automation, e.g. "add a pls automation that opens a URL in the browser I name".

## Settings

| Variable | Effect |
|---|---|
| `PLS_HOME` | Keep the library and history in this folder |
| `PLS_MODEL=off` | Don't use the model; requests match by words |

History is in `~/.local/state/pls/history.jsonl` (or `$XDG_STATE_HOME/pls`, or `$PLS_HOME`).

## Contributing

`swift build` and `swift test` work as is. The project's tasks run through [xc](https://github.com/alexmx/xc):
`xc verify` checks formatting and lint, builds and tests (needs SwiftFormat and SwiftLint), and `xc evals` measures
how well the model picks and fills on a fixed set of requests. [CLAUDE.md](CLAUDE.md) describes the layout.

## License

[MIT](LICENSE)
