#!/bin/zsh
# @pls.name: Keep awake
# @pls.description: Keep the Mac from sleeping for a number of minutes, or let it sleep again
# @pls.param minutes: int(0...1440) = 60 -- How long to stay awake, in minutes; 0 lets it sleep again
# @pls.background: true
# @pls.example: keep my mac awake for 2 hours
# @pls.example: don't let the computer sleep
# @pls.example: let my mac sleep again

# Running it again replaces the job, so minutes 0 ends the last one by printing and exiting.
if (( PLS_MINUTES == 0 )); then
  echo "The Mac can sleep again."
  exit 0
fi
until=$(date -v+"$PLS_MINUTES"M +%H:%M)
echo "Keeping the Mac awake until $until."
exec caffeinate -dims -t $(( PLS_MINUTES * 60 ))
