#!/bin/zsh
# @pls.name: My IP address
# @pls.description: Show this Mac's IP address: public, as the internet sees it, or local, on this network
# @pls.param which: enum(public|local) = public -- Public address on the internet, or local address on this network
# @pls.example: what's my ip
# @pls.example: what's my local ip address

case $PLS_WHICH in
  public)
    ip=$(curl -fsS --max-time 5 https://ifconfig.me) || { echo "Couldn't reach ifconfig.me." >&2; exit 1; }
    echo "Public IP: $ip"
    ;;
  local)
    interface=$(route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')
    ip=$(ipconfig getifaddr "$interface" 2>/dev/null) || { echo "Not connected to a network." >&2; exit 1; }
    echo "Local IP: $ip ($interface)"
    ;;
esac
