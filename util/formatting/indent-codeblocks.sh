#!/usr/bin/env bash
# Formatter for treefmt: ensures non-empty lines inside markdown fenced code
# blocks are indented by at least 2 spaces.

for file in "$@"; do
  awk '
    /^[[:space:]]*```/ {
      in_block = !in_block
      print
      next
    }
    in_block && /[^[:space:]]/ && !/^  / {
      print "  " $0
      next
    }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
done
