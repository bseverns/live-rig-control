#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

restore_file() {
  rel="$1"
  src="$ROOT/.private/$rel"
  dst="$ROOT/$rel"

  if [ ! -f "$src" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  printf 'restored %s\n' "$rel"
}

restore_file "README.md"
restore_file "ios/LiveRigControlApp.xcodeproj/project.pbxproj"
