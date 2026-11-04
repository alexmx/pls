#!/bin/zsh
# Writes compressed copies to <folder>/compressed, leaving the originals alone.
setopt null_glob extended_glob
out="$PLS_FOLDER/compressed"
mkdir -p "$out"
files=("$PLS_FOLDER"/*.(#i)$PLS_FORMAT)
for f in $files; do
  sips -s formatOptions "$PLS_QUALITY" "$f" --out "$out/${f:t}" >/dev/null
done
echo "Compressed ${#files} file(s) into $out"
