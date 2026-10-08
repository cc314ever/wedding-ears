#!/bin/zsh
# Build.command — double-click to compile wedding_ears on this Mac.
# Needs Apple's command-line tools (it offers to install them if missing).
cd "$(dirname "$0")"
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Installing Apple's command-line tools (a window will open; accept, then run this again)."
  xcode-select --install
  exit 0
fi
echo "Compiling wedding_ears…"
swiftc -O -framework ScreenCaptureKit -framework AVFoundation -framework Speech wedding_ears.swift -o wedding_ears && chmod +x wedding_ears "Start Wedding Ears.command" && echo "Done. Now double-click 'Start Wedding Ears.command'."
echo "(Press any key to close.)"
read -r -k 1
