# pls

**Ask for your own scripts in plain words.** pls finds the automation you wrote, fills in its values with Apple's
on-device model, and shows you the plan before anything runs.

![pls finds and runs three automations from plain-language requests](assets/demo.gif)

- **Say it, don't remember it.** No more digging for a script's name, its flags or the folder it lives in.
- **Only your code runs.** The model picks one of your automations and fills its values; it never writes commands.
  Values it filled in are marked `●`, and nothing runs until you say yes.
- **Private.** Apple's on-device model, offline; nothing leaves your Mac.
- **One home for your automations:** shell scripts, AppleScript and Shortcuts, with typed params, history and
  background jobs.
- **Share them.** Put your automations in a GitHub repo and anyone can install them with
  `pls collection add you/repo`. Nothing in a collection runs until they've read it and turned it on.

## Installation

### Homebrew

```bash
brew install alexmx/tools/pls
```

### Mise

```bash
mise use --global github:alexmx/pls
```

pls needs macOS 26 or later. Requests in plain words need Apple Intelligence turned on; without it, pls offers the
closest automations by shared words instead, and everything else works the same.

Tab completion for zsh: add `source <(pls completion zsh)` to `~/.zshrc`, after `compinit`.

## Quick start

Install the everyday automations from [pls-automations](https://github.com/alexmx/pls-automations), turn one on and
ask for it:

```bash
pls collection add alexmx/pls-automations   # everything starts off; answer n to review them later
pls collection enable my-ip                  # read one and turn it on
pls "what's my ip"
```

`pls collection review` goes through the rest. To write your own, see [Writing automations](#writing-automations),
or [let your coding agent write them](#let-your-agent-write-them).

## Usage

```bash
# Run
pls "make the jpgs on my desktop smaller"          # a request in plain words
pls run compress-images ~/Pictures --quality 60    # by id, with values
pls again                                          # the last run, with the same values

# Look around
pls list                                           # your automations
pls show compress-images                           # one in detail
pls history                                        # recent runs
pls jobs                                           # what's running in the background

# Check
pls doctor                                         # problems in your automations
pls doctor --examples kill-port                    # does the model pick it for each of its examples?
```

Before a run, pls shows the plan: each value and where it came from. Answer with one key: Enter or `y` runs it, `e`
edits the values, `n` doesn't run it. `--dry-run` shows what would run without running it, and `--yes` skips the
question.

## Writing automations

Automations live in `~/.config/pls/automations`. A script declares itself in a comment header, and its file name is
its id:

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

Params arrive as `$PLS_<NAME>` variables, and as arguments in order. Their types are `string`, `path`, `bool`,
`int`, `number` and `enum`, with optional ranges, defaults and descriptions. A few more keys:

| Key | Effect |
|---|---|
| `@pls.confirm: true` | Ask before every run, or only for some choices: `action=delete` |
| `@pls.background: true` | Run as a job that `pls jobs` lists and `pls jobs stop <id>` ends |
| `@pls.preview: true` | Let the script say what it would do (it gets `PLS_PREVIEW=1`) before you're asked |

An automation that needs files of its own is a folder with a `manifest.yaml` instead. The
[skill](skills/use-pls/SKILL.md) describes every format in full.

## Collections

Install automations other people share on GitHub, and keep them up to date:

```bash
pls collection add alexmx/pls-automations                        # install, then review what's in it
pls collection add git@github.com:you/private-automations.git    # a private repo, over SSH
pls collection review                                            # read what's off and turn on what you trust
pls collection update                                            # pull the latest
pls collection list                                              # each automation: on, off, or changed
pls collection enable wifi                                       # show one and turn it on
pls collection disable wifi                                      # turn one off
pls collection remove alexmx/pls-automations
```

A collection's scripts run with your full user rights, so pls is careful with them:

- **Nothing runs until you approve it.** Adding a collection asks whether to review: you go through each
  automation's files and turn it on or leave it off.
- **Warnings point at lines worth a look:** deleting files, `sudo`, running downloaded code, sending data out,
  reading secrets, starting itself later, hiding what it does. They're hints, not a security check; reading the
  script is what counts.
- **A change turns it off again.** An approval is for the files as you read them (a SHA-256 over them). When an update
  changes them, the automation is off until you review it again.
- **What you review is everything it runs.** pls won't load an automation whose files, links or entry lead outside
  its own folder.

A collection is a GitHub repo with an `automations/` folder, laid out like your library. It loads alongside your own
automations; when an id is taken, the collection's automation goes by its full name, `alexmx/pls-automations/wifi`.
Needs git (Xcode's command-line tools).

## Let your agent write them

pls ships an [Agent Skill](skills/use-pls/SKILL.md) that teaches coding agents such as Claude Code the formats, how to
write descriptions and params the small on-device model routes and fills well, and how to check the result. Install
it from this repository with any tool that installs skills from GitHub, or from pls itself:

```bash
mkdir -p ~/.claude/skills/use-pls && pls skill > ~/.claude/skills/use-pls/SKILL.md
```

Then ask your agent for an automation: "add a pls automation that opens a URL in the browser I name".

## Settings and files

| Variable | Effect |
|---|---|
| `PLS_HOME` | Keep the library, collections and history in this folder |
| `PLS_MODEL=off` | Don't use the model; requests match by words |

Your automations and collections are in `~/.config/pls/` (or `$XDG_CONFIG_HOME/pls`). History and background jobs,
with each job's output, are in `~/.local/state/pls/` (or `$XDG_STATE_HOME/pls`).

## License

[MIT](LICENSE)
