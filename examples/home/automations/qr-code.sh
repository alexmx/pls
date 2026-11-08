#!/bin/zsh
# @pls.name: QR code
# @pls.description: Draw a QR code for a link or any text in the terminal, to scan with a phone
# @pls.param text: string -- The link or text to put in the QR code
# @pls.example: qr code for github.com/alexmx/pls
# @pls.example: make a qr code of https://example.com

if ! command -v qrencode >/dev/null; then
  echo "This needs qrencode: brew install qrencode" >&2
  exit 1
fi
qrencode -t ansiutf8 -m 1 -- "$PLS_TEXT"
