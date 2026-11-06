#!/bin/zsh
# @pls.description: Turn a macOS Focus mode on or off, optionally for a number of minutes
# @pls.param mode: enum(do-not-disturb|work|sleep|off) = do-not-disturb -- Which Focus
# @pls.param minutes: int(0...1440) = 0 -- How long; 0 means until turned off
# @pls.example: do not disturb for an hour
# @pls.example: turn off focus

# Runs a Shortcut: the way to use Shortcuts with pls. A Shortcut takes one input, so the params go in as JSON.
# Make a Shortcut named "Set Focus" that starts with "Get Dictionary from Input" and reads mode and minutes from it.

input=$(mktemp -t pls-focus) || exit 1
trap 'rm -f "$input"' EXIT
printf '{"mode": "%s", "minutes": %s}\n' "$PLS_MODE" "$PLS_MINUTES" > "$input"
shortcuts run "Set Focus" --input-path "$input"
