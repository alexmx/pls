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
