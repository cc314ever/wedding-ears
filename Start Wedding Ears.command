#!/bin/zsh
# Start Wedding Ears — double-click to run. Built 2026-10-08 (Just Claude is Fine).
# Listens to what this Mac is playing and writes the words to text files, live,
# in each language you choose. Nothing leaves this machine.
cd "$(dirname "$0")"

echo ""
echo "  WEDDING EARS"
echo "  Listens to the stream playing on this Mac and writes the words to text, live."
echo ""
echo "  Before the first run, once per Mac:"
echo "   1. System Settings → Privacy & Security → Screen & System Audio Recording → allow Terminal."
echo "   2. System Settings → Privacy & Security → Speech Recognition → allow Terminal (it will ask)."
echo "   3. For French: System Settings → Keyboard → Dictation → Languages → add French (France)."
echo "   Then quit Terminal and double-click this again."
echo ""
echo "  Which language?  [1] English  [2] French  [3] both (default)"
read -r choice
case "$choice" in
  1) LANGS="en_US" ;;
  2) LANGS="fr_FR" ;;
  *) LANGS="fr_FR,en_US" ;;
esac

OUT="$HOME/Wedding/$(date +%Y-%m-%d_%H%M)"
mkdir -p "$OUT"
echo ""
echo "  Writing to: $OUT"
echo "    fr_FR.txt / en_US.txt   the words, one line per sentence, with the time"
echo "    live.html               the last lines, big — opening it in your browser now"
echo "    audio.caf               the sound, kept beside the words"
echo ""
echo "  Play the stream in a browser or player window. Press Ctrl-C here to stop."
echo ""

# the page needs to exist before the browser opens it
echo '<!doctype html><meta charset=utf-8><meta http-equiv=refresh content=1><body style="background:#111;color:#999;font:28px -apple-system,sans-serif;margin:24px">listening…</body>' > "$OUT/live.html"
open "$OUT/live.html"

./wedding_ears "$OUT" "$LANGS" names.txt fixes.txt
echo ""
echo "  Stopped. Your files are in $OUT"
echo "  (Press any key to close.)"
read -r -k 1
