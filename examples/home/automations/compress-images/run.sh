#!/bin/zsh
# Writes compressed copies to <folder>/compressed, leaving the originals alone.
setopt null_glob extended_glob
out="$QUICK_FOLDER/compressed"
mkdir -p "$out"
files=("$QUICK_FOLDER"/*.(#i)$QUICK_FORMAT)
for f in $files; do
  sips -s formatOptions "$QUICK_QUALITY" "$f" --out "$out/${f:t}" >/dev/null
done
echo "Compressed ${#files} file(s) into $out"
