# pls

Run your own automations from the command line, by name or in plain words.

```
$ pls "something is stuck on port 3000"
→ Kill process on port  (kill-port)

    PARAM  VALUE  FROM
  ● port   3000   from request

  Run?  ⏎ yes · e edit · n no
Killed 1 process(es) on port 3000.
```

pls runs automations you write yourself: shell scripts and AppleScript, which can also run Shortcuts. Each one
declares a description, a few example requests and typed params. Ask in plain words and Apple's on-device model picks
the automation and fills its values; pls shows the plan, with the values the model filled in marked `●`, and asks
before running it. Nothing leaves your Mac.

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
pls doctor --examples kill-port             # check that the model picks it for each of its examples
pls collection add alexmx/pls-automations   # install shared automations (see Collections)
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

A few more keys: `@pls.confirm: true` asks before every run (or `action=delete` only for that choice),
`@pls.background: true` runs it as a job that `pls jobs` lists, and `@pls.preview: true` lets the script say what it
would do (it gets `PLS_PREVIEW=1`) before you're asked and with `--dry-run`. The
[skill](skills/use-pls/SKILL.md) describes the formats in full.

[`examples/home`](examples/home/automations) has one automation in each format, including AppleScript and a Shortcut
wrapper. Try them without touching your own library:

```sh
PLS_HOME=examples/home pls list
PLS_HOME=examples/home pls "turn on dark mode" --dry-run
```

## Collections

Install automations other people share on GitHub, and keep them up to date:

```sh
pls collection add alexmx/pls-automations             # install; everything starts off, and it asks to review
pls collection add git@github.com:you/private-automations.git   # a private repo, over SSH with your GitHub key
pls collection review                                  # read what's off and turn on what you trust
pls collection update                                  # pull the latest; what changed is off until you review it
pls collection enable wifi                             # show one and turn it on
pls collection disable wifi                            # turn one off
pls collection list                                    # each automation: on, off, or changed
pls collection remove alexmx/pls-automations
```

A collection's scripts run with your full user rights, so nothing in one runs until you approve it. Adding or updating
lists warnings for lines worth a look (deleting files, `sudo`, running downloaded code, sending data out, reading
secrets, starting itself later, hiding what it does) and asks whether to review: you go through each automation's
files and turn it on or leave it off, or turn them all on unread. The warnings are hints, not a security check;
reading the script is what counts. An approval is for the files as you read them (a SHA-256 over them): when an update
or anything else changes them, the automation is off again until you review it. So that the review shows everything
an automation runs, pls won't load one whose files, links or entry lead outside its own folder.

A collection is a GitHub repo with an `automations/` folder, laid out like your library; it's cloned into
`~/.config/pls/collections/<owner>/<repo>` and loads alongside your own automations. When an id is taken, the
collection's automation is known by its full name, `alexmx/pls-automations/wifi`; your own automations always keep
theirs. Needs git (Xcode's command-line tools).

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

History and background jobs (`jobs/`, with each job's output) are in `~/.local/state/pls/` (or
`$XDG_STATE_HOME/pls`, or `$PLS_HOME`); collections are in `~/.config/pls/collections/`, next to your automations.

## Contributing

`swift build` and `swift test` work as is. The project's tasks run through [xc](https://github.com/alexmx/xc):
`xc verify` checks formatting and lint, builds and tests (needs SwiftFormat and SwiftLint), and `xc evals` measures
how well the model picks and fills on a fixed set of requests. [CLAUDE.md](CLAUDE.md) describes the layout.

## License

[MIT](LICENSE)
