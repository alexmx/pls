# The README's demo. Re-record with `xc demo` (needs vhs, qrencode and Apple Intelligence).
Output assets/demo.gif

Set Shell bash
Set FontSize 18
Set Width 1100
Set Height 700
Set Padding 24
Set TypingSpeed 45ms
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set CursorBlink false

Env PLS_HOME "examples/home"

Hide
Type `export PATH="$PWD/.build/release:$PATH" PS1='\n$ '; pls run keep-awake 0 >/dev/null; clear`
Enter
Sleep 500ms
Show

Type `pls "what's my local ip"`
Sleep 400ms
Enter
Wait+Screen /Run\?/
Sleep 2s
Type "y"
Sleep 2s

Type `pls "keep my mac awake for 2 hours"`
Sleep 400ms
Enter
Wait+Screen /Run\?/
Sleep 2.5s
Type "y"
Sleep 2.5s

Type `pls "qr code for github.com/alexmx/pls"`
Sleep 400ms
Enter
Wait+Screen /Run\?/
Sleep 2s
Type "y"
Sleep 4s

Hide
Type "pls run keep-awake 0 >/dev/null"
Enter
Sleep 500ms
