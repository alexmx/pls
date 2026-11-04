#!/bin/zsh
# @quick.name: Kill process on port
# @quick.description: Kill whatever process is listening on a TCP port
# @quick.param port: int(1...65535) -- TCP port number
# @quick.example: free up port 3000
# @quick.example: something is stuck on 8080

pids=$(lsof -ti tcp:"$QUICK_PORT")
if [[ -z $pids ]]; then
  echo "Nothing is listening on port $QUICK_PORT."
  exit 0
fi
echo "$pids" | xargs kill && echo "Killed $(echo "$pids" | wc -l | tr -d ' ') process(es) on port $QUICK_PORT."
